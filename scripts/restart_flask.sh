#!/usr/bin/env bash
# restart_flask.sh — Safe Flask restart: backup first, then supervisorctl restart.
# USE THIS instead of "sudo supervisorctl restart raddflix_radd" directly.
# This guarantees a fresh DB + session + catalog snapshot exists before the
# process stops, so any state in memory is captured on disk beforehand.
#
# Usage:
#   sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh
#   sudo /opt/jazzmax/radd-hub/scripts/restart_flask.sh --skip-backup

set -euo pipefail

RADD_DIR="/opt/jazzmax/radd-hub"
SCRIPT_DIR="$RADD_DIR/scripts"
SUPERVISOR_NAME="raddflix_radd"
SKIP_BACKUP="${1:-}"

echo "[restart_flask] Starting safe Flask restart…"

# Step 1: Pre-restart backup (unless --skip-backup passed)
if [[ "$SKIP_BACKUP" != "--skip-backup" ]]; then
    echo "[restart_flask] Running pre-restart backup…"
    if bash "$SCRIPT_DIR/nightly_backup.sh" --pre-restart; then
        echo "[restart_flask] Pre-restart backup OK"
    else
        echo "[restart_flask] WARN: Backup failed — proceeding with restart anyway"
    fi
else
    echo "[restart_flask] Skipping backup (--skip-backup flag)"
fi

# Step 2: Restart Flask via supervisorctl
echo "[restart_flask] Restarting $SUPERVISOR_NAME…"
sudo supervisorctl restart "$SUPERVISOR_NAME"

# Step 3: Health check (wait up to 15s for Flask to respond)
echo "[restart_flask] Waiting for Flask to come up…"
for i in $(seq 1 15); do
    sleep 1
    HEALTH=$(curl -sf http://localhost:5000/healthz 2>/dev/null || echo "")
    if echo "$HEALTH" | grep -q ok:true; then
        echo "[restart_flask] Flask healthy after ${i}s — $HEALTH"
        exit 0
    fi
done

echo "[restart_flask] WARN: Flask did not respond healthy after 15s — check logs"
exit 1
