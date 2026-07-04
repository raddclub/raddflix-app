#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Log Pending Changes (BEFORE editing files)              ║
# ║                                                                      ║
# ║  Run this BEFORE every edit. It writes the commit message and       ║
# ║  file list to agent-hub/UNPUSHED.txt so that if the agent hits      ║
# ║  its context limit before auto_commit.sh runs, the user can         ║
# ║  recover by running: bash recover_push.sh                           ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash log_pending.sh "message" file1 [file2 ...]                  ║
# ║                                                                      ║
# ║  FULL AGENT WORKFLOW every time you change files:                   ║
# ║    1. bash log_pending.sh "message" file1 [file2 ...]               ║
# ║    2. <edit the files>                                               ║
# ║    3. bash auto_commit.sh "message" file1 [file2 ...]               ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

[ "${1:-}" != "" ] || { echo "  ❌ Usage: bash log_pending.sh \"message\" file1 [file2 ...]" >&2; exit 1; }
[ "${2:-}" != "" ] || { echo "  ❌ At least one file path is required" >&2; exit 1; }

COMMIT_MSG="$1"; shift
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PENDING_LOG="$REPO_ROOT/agent-hub/UNPUSHED.txt"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

cat >> "$PENDING_LOG" <<ENTRY

## PENDING — $TIMESTAMP
message: $COMMIT_MSG
files:
$(for f in "$@"; do echo "  - $f"; done)
ENTRY

echo "  ✓ Logged to UNPUSHED.txt: $COMMIT_MSG ($*)"
echo "    Now edit the files, then run: bash auto_commit.sh \"$COMMIT_MSG\" $*"
