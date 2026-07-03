#!/usr/bin/env bash
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

set -uo pipefail
IFS=$'\n\t'

ORACLE_IP="92.4.95.252"
ORACLE_USER="ubuntu"
ORACLE_DIR="/opt/jazzmax"
SERVICE_NAME="raddflix_radd"

KEY_FILE="$(mktemp /tmp/oracle_deploy_key.XXXXXX)"

# Always clean up the private key file, no matter how the script exits
# (success, error, or Ctrl-C) — it must never be left lying around in /tmp.
cleanup() { rm -f "$KEY_FILE"; }
trap cleanup EXIT INT TERM

fail() {
    echo ""
    echo "  ❌ ERROR: $1" >&2
    exit 1
}

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         RaddFlix → Oracle Deploy                  ║"
echo "║         Host: $ORACLE_IP                          ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check required tools ──────────────────────────────────────────────────────
for bin in ssh node curl; do
    command -v "$bin" >/dev/null 2>&1 || fail "required tool '$bin' not found on PATH"
done

# ── Check ORACLE_SSH_KEY ──────────────────────────────────────────────────────
if [ -z "${ORACLE_SSH_KEY:-}" ]; then
    fail "ORACLE_SSH_KEY secret is not set!

  Fix: Replit sidebar → Secrets (🔒) → + Add Secret
       Name:  ORACLE_SSH_KEY
       Value: SSH private key for ubuntu@$ORACLE_IP"
fi

# ── Restore SSH key ───────────────────────────────────────────────────────────
if ! node -e "
const raw = process.env.ORACLE_SSH_KEY || '';
const m = raw.match(/(-----BEGIN[^-]+-----)(.+?)(-----END[^-]+-----)/s);
if (!m) { console.error('  ❌ Could not parse ORACLE_SSH_KEY'); process.exit(1); }
require('fs').writeFileSync(process.argv[1],
    m[1].trim()+'\n'+m[2].trim().replace(/ /g,'\n')+'\n'+m[3].trim()+'\n',
    {mode: 0o600});
" "$KEY_FILE"; then
    fail "failed to restore SSH key from ORACLE_SSH_KEY (check the secret's format)"
fi
chmod 600 "$KEY_FILE"
echo "  ✓ SSH key restored (temp file, auto-deleted on exit)"

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o BatchMode=yes"

# ── Test connection ───────────────────────────────────────────────────────────
echo ""
echo "▶ Testing connection to Oracle..."
if ! CONNECT_OUT=$($SSH "${ORACLE_USER}@${ORACLE_IP}" "echo OK" 2>&1); then
    echo "$CONNECT_OUT" >&2
    fail "cannot connect to Oracle ($ORACLE_IP). Check ORACLE_SSH_KEY, network, and that the host is reachable."
fi
echo "  ✓ Connected to $ORACLE_IP"

# ── Verify target directory + git repo exist before touching anything ────────
echo ""
echo "▶ Verifying remote deploy directory..."
if ! $SSH "${ORACLE_USER}@${ORACLE_IP}" "[ -d '$ORACLE_DIR/.git' ]" 2>/dev/null; then
    fail "$ORACLE_DIR is missing or is not a git repo on $ORACLE_IP. Refusing to proceed."
fi
echo "  ✓ $ORACLE_DIR is a valid git checkout"

# ── Pull latest code (abort on merge conflicts instead of leaving a broken tree) ─
echo ""
echo "▶ Pulling latest code from GitHub..."
PULL_OUTPUT=$($SSH "${ORACLE_USER}@${ORACLE_IP}" "
    set -e
    cd '$ORACLE_DIR'
    if [ -n \"\$(git status --porcelain)\" ]; then
        echo '__DIRTY_WORKTREE__'
        exit 1
    fi
    git fetch --quiet origin
    git merge --ff-only origin/HEAD 2>&1 || { echo '__NON_FF__'; exit 1; }
    echo 'Current commit:' \$(git log --oneline -1)
" 2>&1)
PULL_STATUS=$?

echo "$PULL_OUTPUT"

if [ "$PULL_STATUS" -ne 0 ]; then
    if echo "$PULL_OUTPUT" | grep -q "__DIRTY_WORKTREE__"; then
        fail "$ORACLE_DIR has uncommitted local changes on the server — refusing to pull over them. SSH in and resolve manually."
    elif echo "$PULL_OUTPUT" | grep -q "__NON_FF__"; then
        fail "server branch has diverged from origin (not a fast-forward). Refusing to auto-merge/reset production. SSH in and resolve manually."
    else
        fail "git pull failed on the server (see output above)."
    fi
fi
echo "  ✓ Code updated"

# ── Install any new Python deps (non-fatal, but surfaced clearly) ────────────
echo ""
echo "▶ Installing Python dependencies..."
if ! DEPS_OUTPUT=$($SSH "${ORACLE_USER}@${ORACLE_IP}" "
    cd '$ORACLE_DIR'
    if [ -f requirements.txt ]; then
        pip3 install -r requirements.txt -q --break-system-packages
    else
        echo 'no requirements.txt found — skipping'
    fi
" 2>&1); then
    echo "  ⚠️  dependency install reported an error (deploy will continue, but check manually):"
    echo "$DEPS_OUTPUT" | sed 's/^/    /'
else
    echo "  ✓ Dependencies ready"
fi

# ── Restart Flask server ──────────────────────────────────────────────────────
echo ""
echo "▶ Restarting RaddFlix server..."
if ! RESTART_OUTPUT=$($SSH "${ORACLE_USER}@${ORACLE_IP}" "
    sudo -n supervisorctl restart '$SERVICE_NAME' 2>&1 || exit 1
    sleep 2
    sudo -n supervisorctl status '$SERVICE_NAME'
" 2>&1); then
    echo "$RESTART_OUTPUT" >&2
    fail "could not restart '$SERVICE_NAME' — check that passwordless sudo is configured for supervisorctl, and that the service name is correct."
fi
echo "$RESTART_OUTPUT"

if ! echo "$RESTART_OUTPUT" | grep -qi "RUNNING"; then
    fail "'$SERVICE_NAME' does not report RUNNING after restart. Check logs: ssh to oracle → sudo supervisorctl tail $SERVICE_NAME"
fi
echo "  ✓ Service restarted and RUNNING"

# ── Verify API is responding ──────────────────────────────────────────────────
echo ""
echo "▶ Verifying API..."
sleep 2
API_RESP=$($SSH "${ORACLE_USER}@${ORACLE_IP}" "curl -s --max-time 10 http://localhost:5000/api/app/version" 2>/dev/null || true)

if [ -z "$API_RESP" ]; then
    fail "API did not respond at all after restart — deployment may have broken the server. Check logs immediately: sudo supervisorctl tail $SERVICE_NAME"
elif echo "$API_RESP" | grep -q '"ok"'; then
    echo "  ✅ API responding: $API_RESP"
else
    fail "API responded but not as expected: $API_RESP
     Check logs: ssh to oracle → sudo supervisorctl tail $SERVICE_NAME"
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅ Oracle deploy complete!                      ║"
echo "║   API:   http://$ORACLE_IP/api/app/version"
echo "║   Admin: http://$ORACLE_IP/admin"
echo "╚══════════════════════════════════════════════════╝"
echo ""
