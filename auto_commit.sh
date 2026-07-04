#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  RaddFlix — Auto-Commit & Push                                       ║
# ║                                                                      ║
# ║  Call this after EVERY file edit, big or small. Designed to be      ║
# ║  fast — minimal validation, no heavy API checks.                    ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash auto_commit.sh "describe what you changed"                  ║
# ║    bash auto_commit.sh "fix player zoom" player_screen.dart         ║
# ║    DRY_RUN=1 bash auto_commit.sh "preview only"                     ║
# ║                                                                      ║
# ║  Arguments:                                                          ║
# ║    $1  — commit message (required)                                   ║
# ║    $2+ — specific files to stage (optional; stages ALL if omitted)  ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets (repo scope)           ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

GITHUB_USER="raddclub"
GITHUB_REPO="raddflix-app"
DRY_RUN="${DRY_RUN:-0}"

# Resolve repo root (script lives at the repo root)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
    echo "  ❌ $1" >&2
    exit 1
}

# ── Require commit message ────────────────────────────────────────────────────
COMMIT_MSG="${1:-}"
[ -n "$COMMIT_MSG" ] || fail "Usage: bash auto_commit.sh \"commit message\" [file1 file2 ...]"
shift || true   # remaining args are optional file paths

# ── Require GITHUB_TOKEN ──────────────────────────────────────────────────────
[ -n "${GITHUB_TOKEN:-}" ] || fail "GITHUB_TOKEN secret is not set (Replit sidebar → Secrets)"

# ── Enter repo ────────────────────────────────────────────────────────────────
[ -d "$REPO_ROOT/.git" ] || fail "$REPO_ROOT has no .git — run this from the raddflix-app clone"
cd "$REPO_ROOT"

# ── Guard: no merge/rebase in progress ───────────────────────────────────────
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ]; then
    fail "a merge or rebase is in progress — resolve it first (git status)"
fi

# ── Set git identity (no-op if already configured) ───────────────────────────
git config user.email >/dev/null 2>&1 || git config user.email "agent@raddflix.app"
git config user.name  >/dev/null 2>&1 || git config user.name  "RaddFlix Agent"

# ── Stage files ───────────────────────────────────────────────────────────────
if [ "$#" -gt 0 ]; then
    # Stage only the specific files passed as arguments
    git add -- "$@"
    echo "  Staged: $*"
else
    # Stage everything (most common case)
    git add -A
fi

# ── Check for conflict markers in staged diff ────────────────────────────────
if git diff --cached -U0 | grep -Eq '^\+(<{7}|={7}|>{7})'; then
    fail "staged changes contain unresolved conflict markers — fix before committing"
fi

# ── Guard: no secret-looking files ───────────────────────────────────────────
SUSPECT="$(git diff --cached --name-only | grep -Ei '(^|/)\.env($|\.)|id_rsa$|\.pem$|private.*key' || true)"
[ -z "$SUSPECT" ] || fail "refusing to commit — looks like a secret file: $SUSPECT"

# ── Nothing to commit? ───────────────────────────────────────────────────────
if git diff --cached --quiet; then
    echo "  ✓ Nothing to commit (working tree clean for staged files)"
    exit 0
fi

echo ""
echo "  Files to commit:"
git diff --cached --name-only | sed 's/^/    - /'

[ "$DRY_RUN" = "1" ] && { echo "  ℹ️  DRY_RUN=1 — stopping before commit."; exit 0; }

# ── Commit ────────────────────────────────────────────────────────────────────
git commit -m "$COMMIT_MSG"
echo "  ✓ Committed: $COMMIT_MSG"

# ── Detect branch ────────────────────────────────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" != "HEAD" ] || fail "detached HEAD — checkout a branch before pushing"

# ── Fetch to check if we're behind ───────────────────────────────────────────
git -c http.extraHeader="Authorization: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)" \
    fetch --quiet origin "$BRANCH" 2>/dev/null || true   # first push: remote branch may not exist yet

if git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null 2>&1; then
    BEHIND="$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo 0)"
    if [ "${BEHIND:-0}" != "0" ]; then
        fail "local is $BEHIND commit(s) behind origin/$BRANCH — run: git pull --rebase origin $BRANCH"
    fi
fi

# ── Push ─────────────────────────────────────────────────────────────────────
echo "  → Pushing to github.com/$GITHUB_USER/$GITHUB_REPO ($BRANCH)..."

PUSH_OUT="$(git -c http.extraHeader="Authorization: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)" \
    push origin "HEAD:$BRANCH" 2>&1)" && PUSH_OK=0 || PUSH_OK=$?

echo "$PUSH_OUT" | sed "s/$GITHUB_TOKEN/[TOKEN]/g"
[ "$PUSH_OK" -eq 0 ] || fail "git push failed (see above)"

echo ""
echo "  ✅ Pushed: $COMMIT_MSG"
echo "     https://github.com/$GITHUB_USER/$GITHUB_REPO/commits/$BRANCH"
echo ""
