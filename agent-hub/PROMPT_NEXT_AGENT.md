# RaddFlix — Handoff Prompt for Next Replit Agent

> Copy this entire file and paste it as your first message when starting
> a new Replit Agent session on this project.

---

## Context

You are continuing development of **RaddFlix** — a Pakistani streaming platform
where Jazz SIM users watch movies and dramas for FREE via JazzDrive zero-rating.

- GitHub repo: `raddclub/raddflix-app`
- Oracle server: `ubuntu@92.4.95.252` (port 5000)
- Flutter app: `com.raddflix.app` (Android)
- Admin panel: Flask at `http://92.4.95.252`

## FIRST: Read These Files (mandatory, in order)

```bash
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SKILLS.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/MASTER_TASKLIST.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SECURITY_ARCHITECTURE.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/ZERO_RATING_DELTA.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/TASK_LOG.md"
```

## What Was Done This Session (Phase 25)

1. ✅ **CI Fixed** — `build-apk.yml` now has proper keystore password defaults.
   `KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD || 'RaddFlix_2024_Store' }}`
   The mismatch between keystore-generation step and build step was the failure cause.
   Also added `--obfuscate --split-debug-info` to `flutter build apk --release`.

2. ✅ **AppGuard created** — `lib/core/security/app_guard.dart`
   - APK signature check (silent degradation on tampered APK)
   - Anti-Frida port probe (27042)
   - Root detection
   - Called in `main.dart` before `runApp()`
   - ⚠️ Native channel not yet wired in `MainActivity.kt`
   - ⚠️ Fingerprint placeholder — enforcement not active until real cert SHA set

3. ✅ **RequestEncoder created** — `lib/core/security/request_encoder.dart`
   - XOR API encoding layer (disabled until server side ready)
   - `scrambleUrl()` / `unscrambleUrl()` for share_url at-rest protection
   - ⚠️ NOT yet wired in `local_db.dart`

4. ✅ **Docs updated** — SECURITY_ARCHITECTURE.md (new), ZERO_RATING_DELTA.md (fixed
   wrong "24h link expiry" claim — links NEVER expire), REINCARNATION.md, MASTER_TASKLIST.md,
   TASK_LOG.md all updated.

## What You Must Do Next (in priority order)

### Priority 1 — Verify CI passes
Check if CI is now green after the keystore fix. If still failing, diagnose:
```bash
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=1" \
  | jq -r '.workflow_runs[0] | "\(.conclusion) - \(.head_commit.message)"'
```

### Priority 2 — Wire MainActivity.kt Security Channel
Add native security channel to `MainActivity.kt` for:
- `getSignatureFingerprint` — APK cert SHA-256
- `checkFrida` — memory map scan for Frida agent
- `checkRoot` — su binary check

The exact Kotlin code is in `agent-hub/SECURITY_ARCHITECTURE.md` under
"Native Channel TODO (MainActivity.kt)".

Register on the channel `"com.raddflix.app/security"`.

### Priority 3 — Wire share_url Scrambling in local_db.dart
In `lib/core/db/local_db.dart`, wire `RequestEncoder.scrambleUrl()` and
`.unscrambleUrl()` on all share_url read/write operations:

Key locations:
- `mergeDeltaTitle()` — scramble before storing
- `upsertEpisode()` — scramble `share_url` before insert
- `getShareUrl()` — unscramble on return
- `_persistItems()` in sync_service.dart — scramble Oracle share_urls too

Device ID for the key: `await DeviceId.get()` (see `lib/core/security/device_id.dart`)

### Priority 4 — Get APK Fingerprint and Activate Signature Check
1. Download the APK artifact from GitHub Actions
2. Run: `keytool -printcert -jarfile RaddFlix-*.apk`
3. Copy the SHA-256 fingerprint
4. Update `_officialFingerprint` in `app_guard.dart`
5. Rebuild and redistribute — signature enforcement is now live

### Priority 5 — Server XOR Encoding (Optional)
When ready to activate Layer 5 XOR encoding:
1. Implement `radd-hub/hub/request_encoding.py` (spec in SECURITY_ARCHITECTURE.md)
2. Wire it to all protected API routes
3. Set `RequestEncoder.enabled = true` in Flutter
Deploy both sides SIMULTANEOUSLY — mixed state breaks all API calls.

### Other Open Tasks
See `agent-hub/MASTER_TASKLIST.md` Phase 25 for full security task list.
See the "Open / Next" section at the top of MASTER_TASKLIST.md for all pending work.

---

## Non-Negotiable Rules for ALL Agents

1. **NEVER commit via git commands** — always GitHub Tree API (see SKILLS.md Rule 3)
2. **NEVER force-push** — `"force": false` always
3. **NEVER upgrade `sqflite_sqlcipher` above 3.1.0+1**
4. **NEVER rename `oldV` in `_migrate(Database db, int oldV, int newV)`**
5. **NEVER route JazzDrive SAPI calls through Oracle** — zero-rating requires phone→JazzDrive directly
6. **NEVER write "JazzMAX" or "Zeno"** — the app is RaddFlix
7. **ALWAYS update MASTER_TASKLIST.md and TASK_LOG.md** at end of every session
8. **ALWAYS update REINCARNATION.md** with any major architectural decisions
9. **Share_urls NEVER expire** — any claim they do is wrong
10. **Always read SKILLS.md** before doing anything — it contains critical project rules

## SKILLS.md Location
`agent-hub/SKILLS.md` — contains the GitHub API commit pattern, SSH key reformat,
and all project-specific rules. Read it FIRST before making any commits.

## GitHub Token
`$GITHUB_TOKEN` is set in Replit env — use it directly in curl commands.

## SSH to Oracle
Key is OPENSSH format stored in Replit secrets. See AGENT_NOTES.md or SKILLS.md
for the key reformat recipe (spaces→newlines, PEM header fix).

---

*Handoff written by: Replit Agent, Phase 25, 2026-05-31*
