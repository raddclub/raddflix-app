---
name: Oracle & GitHub access patterns
description: How to SSH into Oracle and push to GitHub — the only patterns that work reliably
---

## SSH Key reconstruction (run at start of every session)

```python
import os, subprocess, re

k = os.environ.get('ORACLE_SSH_KEY', '').strip()
lines = k.split('\\n') if '\\n' in k else [k]
pem = '\n'.join(lines)
if 'BEGIN RSA' in pem and '-----BEGIN RSA' not in pem:
    body = re.sub(r'-----(BEGIN|END) RSA PRIVATE KEY-----', '', pem).strip().replace(' ', '').replace('\n', '')
    wrapped = '\n'.join(body[i:i+64] for i in range(0, len(body), 64))
    pem = f'-----BEGIN RSA PRIVATE KEY-----\n{wrapped}\n-----END RSA PRIVATE KEY-----\n'
with open('/tmp/oracle_key', 'w') as f:
    f.write(pem)
subprocess.run(['chmod', '600', '/tmp/oracle_key'])
```

SSH command template:
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "command"
```

SCP download from Oracle:
```bash
scp -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252:/path/file /tmp/file
```

SCP upload to Oracle:
```bash
scp -i /tmp/oracle_key -o StrictHostKeyChecking=no /tmp/file ubuntu@92.4.95.252:/path/file
```

## GitHub — Trees API only (no git shell ever)

Use Node.js Trees API. Pattern:
1. GET git/refs/heads/main → get current SHA
2. GET git/commits/{sha} → get tree SHA
3. POST git/blobs for each file (base64 content)
4. POST git/trees with base_tree + new blob SHAs
5. POST git/commits with new tree + parent SHA
6. PATCH git/refs/heads/main with new commit SHA

## Edit files on Oracle — safe pattern
**Why:** heredoc with emojis or special characters causes SyntaxErrors in the target file.

1. Write a Python edit script locally (to /tmp/fix_something.py)
2. SCP it to Oracle: `scp -i /tmp/oracle_key /tmp/fix_something.py ubuntu@92.4.95.252:/tmp/`
3. Run it: `ssh ... "python3 /tmp/fix_something.py"`
4. Syntax check: `ssh ... "python3 -c 'import hub.module_name' 2>&1"`
5. Restart Flask: `ssh ... "sudo supervisorctl restart raddflix_radd && sleep 4 && curl -s http://localhost:5000/healthz"`
6. SCP modified file back locally
7. Push to GitHub via Trees API

**Never** write multi-line Python with emojis directly in bash heredocs — the escaping causes unterminated string literals.

## Flask restart + verify
```bash
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 \
  "sudo supervisorctl restart raddflix_radd && sleep 4 && curl -s http://localhost:5000/healthz"
```
Expected: {"ok":true,"version":"3.0.0"}

## Task docs — mandatory at end of session (Rule 0)
- agent-hub/TASKS.md — update with completed tasks
- agent-hub/history/TASK_LOG.md — append session summary
