#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PY=""
if [[ -f "$SCRIPT_DIR/.venv/bin/python" ]]; then
    PY="$SCRIPT_DIR/.venv/bin/python"
else
    for cmd in python3 python; do
        if command -v "$cmd" &>/dev/null; then
            PY="$cmd"
            break
        fi
    done
fi

if [[ -z "$PY" ]]; then
    echo "[ERROR] Python not found. Run bash setup.sh first."
    exit 1
fi

exec "$PY" radd_hub.py run
