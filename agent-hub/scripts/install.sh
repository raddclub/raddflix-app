#!/usr/bin/env bash
# RaddFlix Agent Hub — Install Script
# Run: curl -sL https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/scripts/install.sh | bash
# Requires: ORACLE_SSH_KEY and GITHUB_TOKEN set in environment

set -e

echo ""
echo "========================================"
echo "  RaddFlix Agent Hub — Setup"
echo "========================================"
echo ""

# ── 1. Check required env vars ───────────────────────────────────────────────
if [ -z "$ORACLE_SSH_KEY" ]; then
  echo "ERROR: ORACLE_SSH_KEY is not set."
  echo "  Go to Replit Secrets and paste your Oracle SSH private key as-is"
  exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: GITHUB_TOKEN is not set."
  echo "  Go to Replit Secrets and add GITHUB_TOKEN"
  exit 1
fi

echo "[1/4] Setting up Oracle SSH key..."
printf '%s' "$ORACLE_SSH_KEY" > /tmp/oracle_key
chmod 600 /tmp/oracle_key
echo "      SSH key written to /tmp/oracle_key"

# ── 2. Test Oracle connection ─────────────────────────────────────────────────
echo "[2/4] Testing Oracle server connection..."
ORACLE_TEST=$(ssh -i /tmp/oracle_key -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@92.4.95.252 "echo OK" 2>&1)
if [ "$ORACLE_TEST" = "OK" ]; then
  echo "      Oracle server: CONNECTED"
else
  echo "ERROR: Cannot connect to Oracle server."
  echo "  Output: $ORACLE_TEST"
  echo "  Check that ORACLE_SSH_KEY is correct and server is running."
  exit 1
fi

# ── 3. Test GitHub token ──────────────────────────────────────────────────────
echo "[3/4] Verifying GitHub token..."
GH_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: token $GITHUB_TOKEN" https://api.github.com/repos/raddclub/raddflix-app)
if [ "$GH_STATUS" = "200" ]; then
  echo "      GitHub token: VALID (repo raddclub/raddflix-app accessible)"
else
  echo "ERROR: GitHub token invalid or repo not accessible (HTTP $GH_STATUS)"
  exit 1
fi

# ── 4. Pull agent-hub docs locally ───────────────────────────────────────────
echo "[4/4] Pulling latest agent-hub docs..."
mkdir -p /tmp/agent-hub/history /tmp/agent-hub/projects /tmp/agent-hub/scripts

for F in README.md SKILLS.md SETUP.md PROMPT.md; do
  curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/$F"     -o "/tmp/agent-hub/$F" 2>/dev/null && echo "      Downloaded: $F" || echo "      WARNING: Could not download $F"
done

for F in TASK_LOG.md; do
  curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/history/$F"     -o "/tmp/agent-hub/history/$F" 2>/dev/null && echo "      Downloaded: history/$F" || echo "      WARNING: Could not download $F"
done

for F in radd-hub.md flutter-app.md wa-bot.md; do
  curl -sL "https://raw.githubusercontent.com/raddclub/raddflix-app/main/agent-hub/projects/$F"     -o "/tmp/agent-hub/projects/$F" 2>/dev/null && echo "      Downloaded: projects/$F" || echo "      WARNING: Could not download $F"
done

echo ""
echo "========================================"
echo "  ALL DONE — Ready to work!"
echo "========================================"
echo ""
echo "  Oracle SSH:  /tmp/oracle_key (ready)"
echo "  Agent docs:  /tmp/agent-hub/"
echo ""
echo "  Next steps:"
echo "  1. Read /tmp/agent-hub/README.md"
echo "  2. Read /tmp/agent-hub/history/TASK_LOG.md"
echo "  3. Follow /tmp/agent-hub/SKILLS.md rules"
echo ""
echo "  Start prompt: /tmp/agent-hub/PROMPT.md"
echo ""
