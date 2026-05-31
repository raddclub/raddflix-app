# Environment Setup Guide

## Required Replit Secrets

| Secret | What it is |
|---|---|
| `GITHUB_TOKEN` | GitHub personal access token for `raddclub` account (repo scope) |
| `ORACLE_SSH_KEY` | SSH private key for Oracle server — paste as plain text (no encoding needed) |

---

## SSH Key Decode — CRITICAL, use this exact pattern every session

The key may have embedded spaces when retrieved from Replit secrets. Always use this decode:

```python
python3 -c "
import os, re, subprocess
raw = os.environ['ORACLE_SSH_KEY']
m = re.match(r'(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)', raw, re.DOTALL)
if m:
    header = m.group(1).strip()
    body   = m.group(2).strip().replace(' ', '\n')
    footer = m.group(3).strip()
    pem = header + '\n' + body + '\n' + footer + '\n'
    open('/tmp/oracle_key','w').write(pem)
    subprocess.run(['chmod','600','/tmp/oracle_key'])
    print('SSH key written OK')
"
```

---

## Verify Connections

```bash
# Oracle
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "echo Oracle OK && sudo supervisorctl status"

# GitHub
curl -s -H "Authorization: token $GITHUB_TOKEN" \
  https://api.github.com/repos/raddclub/raddflix-app \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('GitHub OK:', d['full_name'], '| public:', not d.get('private',True))"
```

---

## Server Reference

```
OS:         Ubuntu 24.04 LTS (Oracle Cloud Always Free)
Arch:       aarch64 (ARM64)  ← important for architecture-specific installs
IP:         92.4.95.252
User:       ubuntu
Root dir:   /opt/jazzmax/
Python:     3.12
Java:       OpenJDK 21 (pre-installed)
Supervisor: raddflix_radd (port 5000) — only active service
            (raddflix_watch/port 6000 decommissioned 2026-05-30)
SQLite DB:  /opt/jazzmax/radd-hub/data/raddflix.db
```

---

## GitHub Notes

- **Repo is PUBLIC** — unlimited free GitHub Actions minutes on `ubuntu-latest`
- Active workflows: `build-apk.yml` and `ci-tests.yml`
- All GitHub file writes must use the Contents API (PUT with base64 content + current file SHA)
- Never use git shell commands from Replit main agent
