# RaddFlix — Prompt for Next Agent

**Date**: 2026-05-31  
**Phase**: 28 (next to start)  
**Server**: ubuntu@92.4.95.252 — SSH key in `/tmp/oracle_key` (write from env or prior session)

---

## Quick Status

| Component | Status | Notes |
|-----------|--------|-------|
| Oracle server | ✅ RUNNING | `raddflix_radd` supervisor, port 5000 |
| wa-bot | ✅ RUNNING | `raddflix_wa_bot` supervisor, port 3000 — needs WhatsApp pairing |
| CI (GitHub Actions) | ✅ PASSING | Build APK + RaddFlix CI green on commit 70defac2 |
| APK keystore | ✅ Active | SHA-256: BA:4E:41:2D:...:CD:07 |
| All API endpoints | ✅ 18 endpoints | Health checks passing |
| XOR encoding | ⏸️ Disabled | `RequestEncoder.enabled=false` — activate both sides simultaneously |
| WhatsApp OTP | ⏳ Needs pairing | Bot running, no WA account linked yet |
| SSL/HTTPS | ⏳ Needs domain | Let's Encrypt when domain configured |

---

## Remaining Tasks (Priority Order)

### P1 — WhatsApp Bot Pairing (human action needed)
The wa-bot is running on port 3000 and generating QR codes. To link a WhatsApp account:

```bash
# On Oracle server:
echo "923001234567" > /opt/jazzmax/radd-hub/hub/bots/whatsapp/pairing-number.txt
sudo supervisorctl restart raddflix_wa_bot
# Check logs for 8-digit pairing code:
sudo supervisorctl tail raddflix_wa_bot
# Then: WhatsApp app → Settings → Linked Devices → Link a device → Enter pairing code
```

After pairing, test OTP delivery:
```bash
curl -s -X POST http://127.0.0.1:3000/api/send-message \
  -H "Content-Type: application/json" \
  -d '{"jid":"923001234567@s.whatsapp.net","text":"Test from RaddFlix"}'
```

### P2 — XOR Encoding Activation
Both sides implemented but `RequestEncoder.enabled=false`:
- Server: `radd-hub/hub/request_encoding.py` + `@encoding_supported` decorator ✅
- Flutter: `lib/core/security/request_encoder.dart` with `enabled=false`
- To activate: change `enabled=false` to `enabled=true` in Flutter AND deploy server simultaneously
- **WARNING**: Must be done atomically — one side active breaks all API calls

### P3 — TMDB Miss (Avatar/Dark Knight)
Some titles don't match TMDB metadata. Add manual mappings in admin panel.

### P4 — Let's Encrypt SSL
Needs domain name. Once DNS configured: `certbot --nginx -d yourdomain.com`

---

## Critical Facts (Do NOT forget)

### Keystore / APK Signing
- Keystore: `/tmp/raddflix_new.keystore` (PKCS12, alias: `raddflix`)
- Password (store AND key): `RaddFlix_2026_Secure`
- SHA-256 fingerprint in `app_guard.dart _officialFingerprint`
- **DO NOT regenerate** — changing invalidates all installed APKs

### GitHub
- Repo: `raddclub/raddflix-app`
- GitHub Token: `$GITHUB_TOKEN` in Replit env
- Oracle does NOT have GitHub token — commits from Replit via Tree API
- Oracle Git pulls: `cd /opt/jazzmax/radd-hub && git pull` (uses deploy key)

### Oracle Server
- SSH: `ssh -i /tmp/oracle_key ubuntu@92.4.95.252`
- radd-hub path: `/opt/jazzmax/radd-hub/`
- Data dir: `/opt/jazzmax/radd-hub/data/`
- Supervisor conf: `/etc/supervisor/conf.d/raddflix.conf`
- Flask runs on port 5000, wa-bot on port 3000

### wa-bot
- Code: `/opt/jazzmax/radd-hub/hub/bots/whatsapp/index.js`
- Auth session: `/opt/jazzmax/radd-hub/hub/bots/whatsapp/auth_info/` (created after pairing)
- QR code: `/opt/jazzmax/radd-hub/hub/bots/whatsapp/whatsapp-qr.png`
- Logs: `/var/log/raddflix_wa_bot.out.log` or `bot-debug.log` in bot dir
- Pairing: write phone to `pairing-number.txt`, restart, check logs for 8-digit code
- Status API: `http://127.0.0.1:3000/api/status`

---

## Files Changed in Last 2 Sessions

| File | Change |
|------|--------|
| `raddflix_flutter/lib/core/security/app_guard.dart` | New APK fingerprint |
| `radd-hub/hub/bots/whatsapp/index.js` | NEW: wa-bot Node.js |
| `radd-hub/hub/bots/whatsapp/package.json` | NEW: Baileys dependencies |
| `agent-hub/MASTER_TASKLIST.md` | Phase 26 + 27 added |
| `agent-hub/history/TASK_LOG.md` | Full session history |

---

## Context Files
- `agent-hub/REINCARNATION.md` — full project context
- `agent-hub/MASTER_TASKLIST.md` — all phase history
- `agent-hub/SECURITY_ARCHITECTURE.md` — security design
- `agent-hub/PRODUCT_CONTEXT.md` — product overview
