---
name: Oracle supervisor process name
description: The correct supervisorctl name for the RaddFlix Flask backend on Oracle
---

## The rule
The correct supervisor process name for the RaddFlix Flask backend on Oracle (92.4.95.252) is `raddflix_radd`, NOT `radd-hub`.

**Why:** Multiple attempts using `radd-hub` returned "no such process". Confirmed via `sudo supervisorctl status all` which showed `raddflix_radd RUNNING pid 2989296`. Later restarted as pid 3008136.

**How to apply:**
```bash
sudo supervisorctl restart raddflix_radd
sudo supervisorctl status raddflix_radd
sudo supervisorctl tail -f raddflix_radd
```

## Supervisor config
```
/etc/supervisor/conf.d/raddflix.conf
Process: raddflix_radd
Port: 5000 (localhost only — nginx proxies 80→5000)
Server path: /opt/jazzmax/radd-hub/
```

## Server management (from Replit via SSH)
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl status"
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd"
```

## Second supervisor process
`raddflix_wa_bot` — the WhatsApp bot (Node.js 20). Also on Oracle. Do not confuse with Flask.
