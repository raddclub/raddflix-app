#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║              RaddFlix — Push to GitHub                               ║
# ║                                                                      ║
# ║  Run at the end of every work session to push changes to GitHub.    ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash push_to_github.sh                                            ║
# ║    bash push_to_github.sh "your commit message"   (optional)        ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets                        ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -e

GITHUB_USER="raddclub"
GITHUB_REPO="raddflix-app"
# Resolve to the directory this script lives in (the repo root), not a
# hardcoded workspace path. This script may run inside a subfolder of a
# larger workspace (e.g. cloned into another project) — always target its
# own directory, never assume it IS the workspace root.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         RaddFlix → GitHub Push                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check GITHUB_TOKEN ────────────────────────────────────────────────────────
if [ -z "$GITHUB_TOKEN" ]; then
    echo "  ❌ ERROR: GITHUB_TOKEN secret is not set!"
    echo ""
    echo "  Fix: Replit sidebar → Secrets (🔒) → + Add Secret"
    echo "       Name:  GITHUB_TOKEN"
    echo "       Value: your GitHub Personal Access Token (repo scope)"
    echo ""
    exit 1
fi

echo "  ✓ GITHUB_TOKEN found"

# ── Verify token works ────────────────────────────────────────────────────────
LOGIN=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user" | grep '"login"' | cut -d'"' -f4)
if [ -z "$LOGIN" ]; then
    echo "  ❌ ERROR: GITHUB_TOKEN is invalid or expired — generate a new one"
    exit 1
fi
echo "  ✓ Authenticated as: $LOGIN"

# ── Check repo exists ─────────────────────────────────────────────────────────
echo ""
echo "▶ Checking GitHub repo..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "  ✓ Repo: github.com/$GITHUB_USER/$GITHUB_REPO"
else
    echo "  ❌ Repo not found or no access (HTTP $HTTP_STATUS)"
    exit 1
fi

# ── Verify this directory is actually the raddflix-app git repo ──────────────
cd "$WORKSPACE"

if [ ! -d ".git" ]; then
    echo "  ❌ ERROR: $WORKSPACE has no .git directory."
    echo "     Refusing to run — this script must only ever act on the"
    echo "     raddflix-app repo root, never on a parent/unrelated workspace."
    exit 1
fi

# ── Set git remote ────────────────────────────────────────────────────────────
echo ""
echo "▶ Setting git remote..."

REMOTE_URL="https://$GITHUB_TOKEN@github.com/$GITHUB_USER/$GITHUB_REPO.git"

if git remote get-url origin 2>/dev/null | grep -q "github.com"; then
    git remote set-url origin "$REMOTE_URL"
    echo "  ✓ Remote 'origin' updated"
else
    git remote add origin "$REMOTE_URL" 2>/dev/null || \
    git remote set-url origin "$REMOTE_URL"
    echo "  ✓ Remote 'origin' set"
fi

# ── Configure git identity ────────────────────────────────────────────────────
git config user.email "agent@raddflix.app" 2>/dev/null || true
git config user.name "RaddFlix Agent" 2>/dev/null || true

# ── Commit and push ───────────────────────────────────────────────────────────
echo ""
echo "▶ Committing and pushing..."

git add -A

if git diff --cached --quiet; then
    echo "  ✓ Nothing new to commit — already up to date"
else
    COMMIT_MSG="${1:-RaddFlix update — $(date '+%Y-%m-%d %H:%M')}"
    git commit -m "$COMMIT_MSG"
    echo "  ✓ Committed: $COMMIT_MSG"
fi

echo "  → Pushing to github.com/$GITHUB_USER/$GITHUB_REPO ..."
git push origin main 2>&1 | sed "s/$GITHUB_TOKEN/[TOKEN]/g"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Pushed to: https://github.com/$GITHUB_USER/$GITHUB_REPO"
echo ""
echo "  Next: run bash push_to_oracle.sh to deploy to the server"
echo "══════════════════════════════════════════════════════════════"
echo ""
