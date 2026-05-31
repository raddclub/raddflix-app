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

---

## What Was Done Last Session (Phase 26 — Full Verification + Security Activation)

### Phase 26.1 ✅ — Oracle Deployment
- Pulled all Phase 25 security code (1b26238 → 3a99653) to Oracle
- Restarted `raddflix_radd` — RUNNING ✅
- `tamper_reports` table created and working
- All 19 API endpoints verified ✅

### Phase 26.2 ✅ — Stable Keystore + Fingerprint Activated
- Generated PKCS12 keystore on Oracle (CN=RaddFlix, SHA-256 = `34:D8:99:BE:46:D6:16:DB:43:B1:90:9F:AA:B5:A8:1A:93:76:B3:5C:D2:C0:C9:28:47:04:C8:92:EB:2C:89:5A`)
- Set `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_PASSWORD`, `KEY_ALIAS` GitHub Secrets
- Updated `app_guard.dart` — placeholder replaced with real fingerprint
- **AppGuard signature enforcement is now LIVE**

### Phase 26.3 ✅ — Bug Fixes
- **Plans features** — `mobile_api.py` was reading `p.get("features")` but DB column is `description`. Fixed to `p.get("description")`. Plans API now returns correct feature lists.
- **XOR admin redirect** — `/security/xor-encoding` was using `login_required(lambda)()` pattern causing 500. Fixed to use `is_logged_in()` check directly.

### ⚠️ XOR Admin Still 500
- The `/security/xor-encoding` route still returns 500 after fix — root cause unknown (Flask error handler hides traceback). The `render_template_string` might be failing due to Jinja2 syntax in the HTML string (use of `{` braces). **Not critical** — admin-only diagnostic page.

---

## Current Server State (as of Phase 26)

| Item | Value |
|------|-------|
| Git HEAD (Oracle) | `3a99653` |
| Git HEAD (GitHub) | `3a99653` |
| Supervisor | `raddflix_radd` RUNNING |
| Titles | 24 published, all TMDB-enriched |
| Plans | Basic Rs.149 / Standard Rs.249 / Premium Rs.399 — all with features |
| CI | ✅ Build APK + RaddFlix CI both running for 3a99653 |

---

## Security Layer Status (FINAL — all 6 layers active or deployed)

```
Layer 1: AppGuard (Dart + Kotlin MethodChannel)         ✅ ENFORCING
  - APK fingerprint: 34:D8:99:BE:... (stable — KEYSTORE_BASE64 set in GitHub Secrets)
  - Frida detection + Root detection wired

Layer 2: Silent Degradation (ApiClient._TamperInterceptor) ✅ DONE
  - When isTampered: returns fake empty responses silently

Layer 3: Share URL at-rest encryption                   ✅ DONE
  - JazzDrive share_urls stored XOR-scrambled with device ID key (RF1: prefix)

Layer 4: Build obfuscation                              ✅ DONE
  - flutter build apk --obfuscate --split-debug-info in CI

Layer 5: API XOR encoding                               ✅ Server deployed
  - request_encoding.py live; Flutter RequestEncoder.enabled=false
  - Activate via RemoteConfig or APK update + Oracle deploy (BOTH sides simultaneously)

Layer 6: Security telemetry                             ✅ LIVE
  - Tamper reports stored in tamper_reports table
  - 2 test entries confirmed stored in DB
  - Admin panel at /security/tamper-reports (requires login)
```

---

## Priority Queue for Next Agent

### Priority 1 — XOR Admin Page Fix (minor)
The `/security/xor-encoding` admin page returns 500. Suspected cause: Jinja2 template
syntax conflict with `{` and `}` characters in the HTML string in `render_template_string`.
Fix: escape braces as `{{` / `}}` or use `jinja2.Environment().from_string()` like
`security_telemetry.py` does.

### Priority 2 — wa-bot Deployment
wa-bot directory is empty on Oracle and NOT in GitHub repo. The WhatsApp bot code
needs to be created/deployed. Currently OTP is stored in DB but not delivered.
This blocks device-switch OTP flow.

### Priority 3 — AppConstants.supportWhatsApp
`lib/core/constants.dart` has `supportWhatsApp = '923XXXXXXXXX'` placeholder.
Update to real support phone number before production release.

### Priority 4 — XOR API Encoding Activation (optional)
When ready to activate end-to-end XOR:
1. Server is ready (`request_encoding.py` deployed)
2. Set `RequestEncoder.enabled = true` in `request_encoder.dart`
3. Wire `@encoding_supported` decorator to Flask routes
4. Deploy BOTH sides simultaneously — mixed state breaks all API calls

### Priority 5 — Phase 27: New Features
Check MASTER_TASKLIST for any new phase tasks.

---

## Non-Negotiable Rules (ALL Agents)

1. **NEVER commit via git commands** — always GitHub Tree API (SKILLS.md Rule 3)
2. **NEVER force-push** — `"force": false` always
3. **NEVER upgrade `sqflite_sqlcipher` above 3.1.0+1**
4. **NEVER rename `oldV` in `_migrate(Database db, int oldV, int newV)`**
5. **NEVER route JazzDrive SAPI calls through Oracle** — zero-rating = phone→JazzDrive directly
6. **NEVER write "JazzMAX" or "Zeno"** — the app is RaddFlix
7. **ALWAYS update MASTER_TASKLIST.md and TASK_LOG.md** at end of every session
8. **ALWAYS update REINCARNATION.md** with major architectural decisions
9. **Share_urls NEVER expire** — any claim they do is wrong
10. **ALWAYS read SKILLS.md** before doing anything

## Critical Code Facts
- `DeviceIdentifier.getDeviceId()` is the XOR key class — NOT `DeviceId`
- `RequestEncoder.enabled = false` (default) — NEVER enable without deploying server decode
- `AppGuard._officialFingerprint = '34:D8:99:BE:...'` — enforcement LIVE, uses stable keystore
- `RF1:` prefix marks scrambled share_urls — plain URLs pass through unscrambled (backward compat)
- Plans `description` column in DB = JSON features array for Flutter app display
- Oracle DB path: `/opt/jazzmax/radd-hub/data/radd_hub.db`

## GitHub Token
`$GITHUB_TOKEN` is set in Replit env — use it directly in curl commands.

## SSH to Oracle
Key is OPENSSH format. Use this reformat recipe (confirmed working):
```python
import os, re
raw = os.environ['ORACLE_SSH_KEY']
m = re.match(r'(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)', raw, re.DOTALL)
if m:
    header = m.group(1).strip()
    body   = m.group(2).strip().replace(' ', '\n')
    footer = m.group(3).strip()
    pem = header + '\n' + body + '\n' + footer + '\n'
    with open('/tmp/oracle_key', 'w') as f:
        f.write(pem)
    os.chmod('/tmp/oracle_key', 0o600)
```

---

*Handoff written by: Replit Agent, Phase 26 complete, 2026-05-31*
