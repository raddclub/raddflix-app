# Agent Starter Prompt

Copy the block below and paste it as your first message to any new AI agent.
Replace the last line with your actual task.

---

```
You are working on RaddFlix — a Pakistani streaming platform.

GitHub: raddclub/raddflix-app (PUBLIC repo)
Oracle: ubuntu@92.4.95.252
Secrets in Replit: $GITHUB_TOKEN, $ORACLE_SSH_KEY

== STEP 1: Decode SSH key (run this first) ==
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
    print('SSH ready')
"

== STEP 2: Verify connections ==
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "echo OK && sudo supervisorctl status"
curl -s -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/raddclub/raddflix-app | python3 -c "import sys,json; d=json.load(sys.stdin); print('GitHub OK:',d['full_name'])"

== STEP 3: Read context files before doing anything ==
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/REINCARNATION.md"
curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/SKILLS.md"

Also read TASK_LOG (last 80 lines):
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/agent-hub/history/TASK_LOG.md" \
  | python3 -c "import sys,json,base64; c=base64.b64decode(json.load(sys.stdin)['content']).decode(); print('\n'.join(c.split('\n')[-80:]))"

== STEP 4: After finishing, append to TASK_LOG ==
Format in SKILLS.md Rule 8. Use GitHub Contents API (PUT with base64 + SHA).

My task today: [DESCRIBE YOUR TASK HERE]
```

---

## Useful shell one-liners (paste after SSH is set up)

```bash
# Check Oracle services
ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no ubuntu@92.4.95.252 "sudo supervisorctl status"

# Check latest CI/build runs
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/runs?per_page=5" | \
  python3 -c "import sys,json; [print(r['id'],r['status'],r.get('conclusion','-'),r['name'][:22],r['head_sha'][:8]) for r in json.load(sys.stdin)['workflow_runs']]"

# Trigger a new APK build
curl -s -X POST -H "Authorization: token $GITHUB_TOKEN" -H "Content-Type: application/json" \
  "https://api.github.com/repos/raddclub/raddflix-app/actions/workflows/build-apk.yml/dispatches" \
  -d '{"ref":"main"}'

# Read any file from GitHub (get content + SHA)
curl -sL -H "Authorization: token $GITHUB_TOKEN" \
  "https://api.github.com/repos/raddclub/raddflix-app/contents/PATH/TO/FILE" | \
  python3 -c "import sys,json,base64; j=json.load(sys.stdin); print('SHA:',j['sha']); print(base64.b64decode(j['content']).decode())"
```
