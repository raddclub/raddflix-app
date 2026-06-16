#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo
echo " ────────────────────────────────────────────────"
echo "  Radd Hub v3.0 — Setup Script"
echo " ────────────────────────────────────────────────"
echo

PYTHON=""
for candidate in python3.12 python3.11 python3.10 python3 python; do
    if command -v "$candidate" &>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [[ -z "$PYTHON" ]]; then
    echo "[ERROR] Python 3.10+ not found."
    exit 1
fi

"$PYTHON" radd_hub.py setup --fix

echo
echo " Setup complete! Ready to run."
echo " Start with: bash start.sh"
echo
