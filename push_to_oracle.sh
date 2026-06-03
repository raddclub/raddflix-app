#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║              RaddFlix — Deploy to Oracle Server                      ║
# ║                                                                      ║
# ║  Pulls latest GitHub code on Oracle and restarts the server.        ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash push_to_oracle.sh                                            ║
# ║                                                                      ║
# ║  REQUIREMENT: ORACLE_SSH_KEY in Replit Secrets                      ║
# ║  Push to GitHub first: bash push_to_github.sh                       ║
# ╚══════════════════════════════════════════════════════════════════════╝

ORACLE_IP="92.4.95.252"
ORACLE_USER="ubuntu"
ORACLE_DIR="/opt/jazzmax"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         RaddFlix → Oracle Deploy                  ║"
echo "║         Host: $ORACLE_IP                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check ORACLE_SSH_KEY ──────────────────────────────────────────────────────
if [ -z "$ORACLE_SSH_KEY" ]; then
    echo "  ❌ ERROR: ORACLE_SSH_KEY secret is not set!"
    echo ""
    echo "  Fix: Replit sidebar → Secrets (🔒) → + Add Secret"
    echo "       Name:  ORACLE_SSH_KEY"
    echo "       Value: SSH private key for ubuntu@$ORACLE_IP"
    echo ""
    exit 1
fi

# ── Restore SSH key ───────────────────────────────────────────────────────────
KEY_FILE="/tmp/oracle_deploy_key"
node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (m) {
    require('fs').writeFileSync('$KEY_FILE',
        m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
        {mode: 0o600});
    console.log('  ✓ SSH key restored');
} else {
    console.error('  ❌ Could not parse ORACLE_SSH_KEY');
    process.exit(1);
}
"

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=15"

# ── Test connection ───────────────────────────────────────────────────────────
echo ""
echo "▶ Testing connection to Oracle..."
if ! $SSH ${ORACLE_USER}@${ORACLE_IP} "echo OK" > /dev/null 2>&1; then
    echo "  ❌ Cannot connect to Oracle ($ORACLE_IP)"
    rm -f "$KEY_FILE"
    exit 1
fi
echo "  ✓ Connected to $ORACLE_IP"

# ── Pull latest code ──────────────────────────────────────────────────────────
echo ""
echo "▶ Pulling latest code from GitHub..."
$SSH ${ORACLE_USER}@${ORACLE_IP} "
    cd $ORACLE_DIR
    git pull 2>&1 | tail -5
    echo 'Current commit:' \$(git log --oneline -1)
"

# ── Install any new Python deps ───────────────────────────────────────────────
echo ""
echo "▶ Installing Python dependencies..."
$SSH ${ORACLE_USER}@${ORACLE_IP} "
    cd $ORACLE_DIR
    pip3 install -r requirements.txt -q --break-system-packages 2>/dev/null | tail -2 || true
    echo '  ✓ Dependencies ready'
"

# ── Restart Flask server ──────────────────────────────────────────────────────
echo ""
echo "▶ Restarting RaddFlix server..."
$SSH ${ORACLE_USER}@${ORACLE_IP} "
    sudo supervisorctl restart raddflix_radd 2>&1
    sleep 2
    sudo supervisorctl status raddflix_radd
"

# ── Verify API is responding ──────────────────────────────────────────────────
echo ""
echo "▶ Verifying API..."
sleep 2
API_RESP=$($SSH ${ORACLE_USER}@${ORACLE_IP} "curl -s http://localhost:5000/api/app/version" 2>/dev/null)
if echo "$API_RESP" | grep -q '"ok"'; then
    echo "  ✅ API responding: $API_RESP"
else
    echo "  ⚠️  API check: $API_RESP"
    echo "  Check logs: ssh to oracle → sudo supervisorctl tail raddflix_radd"
fi

rm -f "$KEY_FILE"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅ Oracle deploy complete!                      ║"
echo "║   API:   http://$ORACLE_IP/api/app/version ║"
echo "║   Admin: http://$ORACLE_IP/admin           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
