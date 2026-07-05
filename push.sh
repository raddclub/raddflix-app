#!/bin/bash
# Run this from the Replit Shell to push ALL unpushed changes to GitHub.
# Usage:  bash push.sh
#    or:  bash push.sh "optional message"

cd "$(dirname "$0")"

if git diff --quiet && git diff --cached --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "✅ Nothing to push — workspace is clean."
  exit 0
fi

MSG="${1:-manual push: workspace sync $(date '+%Y-%m-%d %H:%M')}"

git add -A
git commit -m "$MSG"
git push origin main

echo ""
echo "✅ Pushed to GitHub."
echo "   View: https://github.com/raddclub/raddflix-app/commits/main"
