#!/usr/bin/env bash
# nightly_backup.sh — Nightly DB + db_update.json + session snapshot for RaddFlix
# Runs via cron at 02:00 daily. Also called by restart_flask.sh before restarts.
# Keeps 14 nightly backups of each type; rolling hourly backups handled by self_heal.py.
# Usage: ./nightly_backup.sh [--pre-restart]
#
# Backup targets:
#   radd_hub.db           — main SQLite DB (WAL-safe copy via Python)
#   jazzdrive_session.json — JD tokens (used for DB recovery after a wipe)
#   db_update.json         — Flutter catalog file (so catalog survives DB wipes)

set -euo pipefail

RADD_DIR="/opt/jazzmax/radd-hub"
DATA_DIR="$RADD_DIR/data"
BACKUP_DIR="$DATA_DIR/backups"
LOG="$BACKUP_DIR/nightly.log"
KEEP=14  # keep last 14 nightly backups of each type
MODE="${1:-}"

TS=$(date +"%Y%m%d_%H%M%S")
TAG="nightly"
[[ "$MODE" == "--pre-restart" ]] && TAG="pre-restart"

mkdir -p "$BACKUP_DIR"
exec >> "$LOG" 2>&1

echo ""
echo "========================================"
echo "[$TS] radd-backup START (mode=$TAG)"
echo "========================================"

# ── 1. SQLite DB — WAL-safe backup via Python sqlite3.backup() ───────────────
DB_SRC="$DATA_DIR/radd_hub.db"
DB_DST="$BACKUP_DIR/radd_hub.${TAG}.${TS}.db"
if [[ -f "$DB_SRC" ]]; then
    python3 - "$DB_SRC" "$DB_DST" << PY_EOF
import sqlite3, sys
src, dst = sys.argv[1], sys.argv[2]
src_con = sqlite3.connect(src, timeout=10)
dst_con = sqlite3.connect(dst, timeout=10)
src_con.backup(dst_con)
dst_con.close(); src_con.close()
PY_EOF
    SIZE=$(du -sh "$DB_DST" | cut -f1)
    echo "[DB]  Backed up radd_hub.db → $DB_DST ($SIZE)"
else
    echo "[DB]  WARN: radd_hub.db not found at $DB_SRC — skipping"
fi

# ── 2. jazzdrive_session.json — JD token file (recovery lifeline) ───────────
JD_SRC="$DATA_DIR/jazzdrive_session.json"
JD_DST="$BACKUP_DIR/jazzdrive_session.${TAG}.${TS}.json"
if [[ -f "$JD_SRC" ]]; then
    cp "$JD_SRC" "$JD_DST"
    echo "[JD]  Backed up jazzdrive_session.json → $JD_DST"
else
    echo "[JD]  WARN: jazzdrive_session.json not found — skipping"
fi

# ── 3. db_update.json — Flutter catalog (survives DB wipe) ─────────────────
DBU_SRC="$DATA_DIR/db_update.json"
DBU_DST="$BACKUP_DIR/db_update.${TAG}.${TS}.json"
if [[ -f "$DBU_SRC" ]]; then
    cp "$DBU_SRC" "$DBU_DST"
    TITLES=$(python3 -c "import json; d=json.load(open()); print(len(d.get(titles,[])))" 2>/dev/null || echo "?")
    echo "[CATALOG] Backed up db_update.json → $DBU_DST ($TITLES titles)"
else
    echo "[CATALOG] WARN: db_update.json not found — skipping"
fi

# ── 4. Prune old nightly / pre-restart backups (keep KEEP most recent) ──────
prune_type() {
    local pattern="$1"
    local label="$2"
    # list oldest first, delete until ≤ KEEP remain
    local files=()
    while IFS= read -r f; do files+=("$f"); done < <(ls -t "$BACKUP_DIR"/$pattern 2>/dev/null | tac)
    local total=${#files[@]}
    if (( total > KEEP )); then
        local to_delete=$(( total - KEEP ))
        echo "[PRUNE] Removing $to_delete old $label backup(s)"
        for f in "${files[@]:0:$to_delete}"; do
            rm -f "$f"
        done
    fi
}

prune_type "radd_hub.nightly.*.db"        "nightly DB"
prune_type "radd_hub.pre-restart.*.db"    "pre-restart DB"
prune_type "jazzdrive_session.nightly.*.json"     "nightly JD session"
prune_type "jazzdrive_session.pre-restart.*.json" "pre-restart JD session"
prune_type "db_update.nightly.*.json"     "nightly catalog"
prune_type "db_update.pre-restart.*.json" "pre-restart catalog"

echo "[$TS] radd-backup DONE"
