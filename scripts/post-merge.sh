#!/bin/bash
# Runs automatically after a Replit task-agent merge.
# Must not fail — every command uses || true.

echo "==> post-merge: installing Python packages..."
pip3 install -r requirements.txt -q 2>/dev/null || true

echo "==> post-merge: pnpm install..."
if [ -f pnpm-lock.yaml ]; then
    pnpm install --frozen-lockfile 2>/dev/null || true
fi

echo "==> post-merge: done"
