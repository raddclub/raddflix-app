# NEXT AGENT BRIEFING — RaddFlix
_Written: 2026-06-10 | Updated: 2026-06-21 | Build #1218 ✅_

> ⚠️ Read `agent-hub/HANDOFF_NEXT.md` and `agent-hub/AGENT_STATUS.md` first.
> This file covers architecture and critical rules (still valid).

---

## Who You Are / What This Project Is

You manage the **RaddFlix** Pakistani Flutter streaming app.
- Oracle server: `ubuntu@92.4.95.252` — Flask hub runs here (port 5000, not public)
- GitHub repo: `raddclub/raddflix-app`
- APK CI: `.github/workflows/build-apk.yml` (workflow id: 282572869)
- Flutter app: `raddflix_flutter/`
- Player file: `raddflix_flutter/lib/screens/player_screen.dart` (7071 lines, 21 classes)
- Push script: `node /tmp/push.js` (always fetch fresh SHA before PUT)

---

## CRITICAL RULES — NEVER BREAK

1. `db.setting(k)` NOT `db.get_setting(k)`
2. GitHub pushes via **Contents API** (`/tmp/push.js`) — Replit sandbox blocks git shell
3. `sqflite_sqlcipher` pinned at `3.1.0+1` — NEVER upgrade in Flutter
4. XOR padding fix must stay in `request_encoder.dart` — removing it breaks ALL API calls
5. `androidAttachSurfaceAfterVideoParameters: true` — NEVER add this
6. NO `vf=` property on the player — destroys GL surface on MediaTek (15-day bug)
7. NO local var named `_np` — shadows the mpv instance
8. Proxy background scanning permanently removed — do NOT re-add threads to ProxyPool
9. JazzDrive share keys: the long suffix is PART of the real key — NEVER truncate
10. Add tasks to `TASKS.md` BEFORE making changes

---

## Latest Player Work (2026-06-21)

### Completed
- Phase 13: All showModalBottomSheet → right-side showGeneralDialog panels (45% width, 60% dark)
- Phase 14: MX Player-style brightness (LEFT, amber) + volume (RIGHT, white/orange) vertical pills
- Phase 15: Auto-rotation via native Android SCREEN_ORIENTATION_SENSOR (com.raddflix.app/orient)
- Phase 16: Customizable persistent sidebar — toggle, scroll, 19 shortcuts, drag reorder, add/remove, persisted prefs

### Known Bugs (Priority Order)
1. **BUG-01** — Subtitle alignment silent no-op (sub-margin-y not applied)
2. **BUG-02** — Subtitle background style not applied
3. **BUG-03** — Settings panel init has hardcoded defaults
4. **Top bar overflow** — 12+ icons overflow on small screens

---

## BUGS TO FIX (Backend — Priority Order)

### BUG-1 — delta_push pipeline broken (HIGH PRIORITY)
**File:** `/opt/jazzmax/radd-hub/hub/routes/delta_push.py`
The delta push route is not correctly applying all delta fields.
Verify with: check payload schema vs handler field mapping.

---

## Environment Quick Reference

```bash
# Oracle server
ssh -i /tmp/oracle_key ubuntu@92.4.95.252
sudo supervisorctl restart raddflix_radd
tail -f /opt/jazzmax/radd-hub/data/logs/raddhub.log

# GitHub push
node /tmp/push.js

# Trigger build
curl -X POST -H "Authorization: Bearer $GITHUB_TOKEN" \
  https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/282572869/dispatches \
  -d '{"ref":"main"}'

# Check build
https://github.com/raddclub/raddflix-app/actions
```
