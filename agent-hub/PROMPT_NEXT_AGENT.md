# RaddFlix — Prompt for Next Agent

**Date**: 2026-05-31  
**Phase**: 29 (next to start)  
**Server**: ubuntu@92.4.95.252 — SSH key in `/tmp/oracle_key`

---

## Quick Status

| Component | Status | Notes |
|-----------|--------|-------|
| Oracle Flask server | ✅ RUNNING | `raddflix_radd` supervisor, port 5000 |
| wa-bot | ✅ RUNNING | `raddflix_wa_bot` supervisor, port 3000 — needs WhatsApp pairing |
| CI (GitHub Actions) | ✅ PASSING | Both checks green |
| APK keystore | ✅ Active | SHA-256: BA:4E:41:2D:...:CD:07 |
| XOR encoding | ✅ ACTIVE | Both Flutter + server live — DO NOT disable without both-sides deploy |
| WhatsApp OTP bot | ⏳ Pairing pending | Bot running, pairing code: `4KADV5JQ` for 923257719165 |
| SSL/HTTPS | ⏳ Needs domain | Let's Encrypt when domain configured |

---

## WhatsApp Pairing — PENDING (user action)

**Pairing code**: `4KADV5JQ` (may have rotated — check logs)  
**Phone**: 923257719165 (user's number: 03257719165)

```bash
# Check current pairing code:
curl http://127.0.0.1:3000/api/status
# Or check logs:
sudo supervisorctl tail raddflix_wa_bot

# To get a fresh pairing code (if current expired):
sudo supervisorctl restart raddflix_wa_bot
sleep 5
tail -5 /opt/jazzmax/radd-hub/hub/bots/whatsapp/bot-debug.log
```

Steps for user:
1. Open WhatsApp on phone 03257719165
2. Settings → Linked Devices → Link a Device → Link with phone number
3. Enter the 8-digit pairing code from the bot logs

---

## XOR Encoding — ACTIVE

Both sides active as of commit `f726a0f`. Architecture:

```
Flutter:  _XorInterceptor → X-Encoded:1 + X-Device-Id header
          POST bodies XOR-encoded; responses decoded from octet-stream

Server:   XorWsgiMiddleware — decodes request body before Flask sees it
          _xor_encode_response — encodes /api/* JSON responses
          Key: SHA-256("raddflix_xor_v1:deviceId:day:hour")[:32]
```

**DO NOT change XOR without both sides simultaneously.**

---

## Remaining Tasks

### P1 — WhatsApp account pairing (human action)
See above. Once paired, test OTP with:
```bash
# Trigger device-switch OTP:
curl -X POST http://127.0.0.1:5000/api/auth/device-switch/request \
  -H "Content-Type: application/json" \
  -d '{"phone":"03001234567"}'
# Check bot sends WA message to registered user
```

### P2 — SSL/HTTPS (human: configure domain)
Once domain DNS → 92.4.95.252:
```bash
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d yourdomain.com
```

### P3 — TMDB misses (Avatar / Dark Knight)
Manual mapping in admin panel: `/admin/library` → edit title → set TMDB ID.

---

## Critical Facts

### XOR Layer
- `request_encoding.py` has `XorWsgiMiddleware`; `app.py` has `_xor_encode_response`
- `after_request` MUST use `from flask import request as _req` (module-level import causes NameError)
- Only `/api/*` routes are XOR-encoded (admin panel gets plain JSON)

### Keystore
- Password (store + key): `RaddFlix_2026_Secure` (PKCS12 quirk — both must match)
- Alias: `raddflix`
- **DO NOT regenerate** — invalidates all installed APKs

### wa-bot
- Auth session: saved to `auth_info/` after pairing (persists across restarts)
- Change `autostart=false` → `autostart=true` in supervisor AFTER successful pairing
- File IPC: bot polls `/tmp/radd_bot_cmd/*.in.json` for Python wrapper compatibility

### GitHub
- Commits from Replit via Tree API only (Oracle has no GitHub token)
- Oracle deploy key pulls: `cd /opt/jazzmax/radd-hub && git pull`

---

## Phase History (last 5)
- **Phase 24**: Full system verification
- **Phase 25**: Security architecture (AppGuard, XOR, tamper telemetry)
- **Phase 26**: CI fix, new keystore, APK fingerprint
- **Phase 27**: wa-bot Node.js deployed (Baileys, port 3000)
- **Phase 28**: XOR encoding ACTIVATED both sides, WA pairing code generated
