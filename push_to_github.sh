#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║              RaddFlix — Push to GitHub                               ║
# ║                                                                      ║
# ║  Run at the end of every work session to push changes to GitHub.    ║
# ║                                                                      ║
# ║  HOW TO RUN:                                                         ║
# ║    bash push_to_github.sh                                            ║
# ║    bash push_to_github.sh "your commit message"   (optional)        ║
# ║    DRY_RUN=1 bash push_to_github.sh                (preview only)   ║
# ║                                                                      ║
# ║  REQUIREMENT: GITHUB_TOKEN in Replit Secrets (repo scope)           ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail
IFS=$'\n\t'

GITHUB_USER="raddclub"
GITHUB_REPO="raddflix-app"
DRY_RUN="${DRY_RUN:-0}"

# Resolve to the directory this script lives in (the repo root), not a
# hardcoded workspace path. This script may run inside a subfolder of a
# larger workspace (e.g. cloned into another project) — always target its
# own directory, never assume it IS the workspace root.
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Single global lock — prevents two sessions from racing a commit/push
# against the same working tree (partial commits, interleaved index state).
LOCK_FILE="$WORKSPACE/.push_to_github.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
    echo "  ❌ ERROR: another push_to_github.sh run is already in progress"
    echo "     (lock: $LOCK_FILE). Wait for it to finish, or remove the lock"
    echo "     file manually if you're sure no other run is active."
    exit 1
fi

fail() {
    echo ""
    echo "  ❌ ERROR: $1" >&2
    exit 1
}

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         RaddFlix → GitHub Push                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Check required tools ──────────────────────────────────────────────────────
for bin in git curl node; do
    command -v "$bin" >/dev/null 2>&1 || fail "required tool '$bin' not found on PATH"
done

# ── Check GITHUB_TOKEN ────────────────────────────────────────────────────────
if [ -z "${GITHUB_TOKEN:-}" ]; then
    fail "GITHUB_TOKEN secret is not set!

  Fix: Replit sidebar → Secrets (🔒) → + Add Secret
       Name:  GITHUB_TOKEN
       Value: your GitHub Personal Access Token (repo scope)"
fi
echo "  ✓ GITHUB_TOKEN found"

# ── Verify token works (fail fast with a clear timeout, not a hang) ──────────
USER_JSON="$(curl -sS --fail --max-time 15 \
    -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user")" || fail "could not reach GitHub API (network issue or invalid token)"

LOGIN="$(printf '%s' "$USER_JSON" | node -e '
let d="";process.stdin.on("data",c=>d+=c);
process.stdin.on("end",()=>{try{const j=JSON.parse(d);process.stdout.write(j.login||"");}catch(e){}});
')"
[ -n "$LOGIN" ] || fail "GITHUB_TOKEN is invalid or expired — generate a new one"
echo "  ✓ Authenticated as: $LOGIN"

# ── Check repo exists and token has write access ─────────────────────────────
echo ""
echo "▶ Checking GitHub repo..."
REPO_JSON="$(curl -sS --max-time 15 \
    -H "Authorization: token $GITHUB_TOKEN" \
    -w $'\n%{http_code}' \
    "https://api.github.com/repos/$GITHUB_USER/$GITHUB_REPO")"
HTTP_STATUS="$(printf '%s' "$REPO_JSON" | tail -1)"
REPO_BODY="$(printf '%s' "$REPO_JSON" | sed '$d')"

[ "$HTTP_STATUS" = "200" ] || fail "repo not found or no access (HTTP $HTTP_STATUS)"

CAN_PUSH="$(printf '%s' "$REPO_BODY" | node -e '
let d="";process.stdin.on("data",c=>d+=c);
process.stdin.on("end",()=>{try{const j=JSON.parse(d);process.stdout.write(String(!!(j.permissions&&j.permissions.push)));}catch(e){process.stdout.write("false");}});
')"
DEFAULT_BRANCH="$(printf '%s' "$REPO_BODY" | node -e '
let d="";process.stdin.on("data",c=>d+=c);
process.stdin.on("end",()=>{try{const j=JSON.parse(d);process.stdout.write(j.default_branch||"main");}catch(e){process.stdout.write("main");}});
')"

[ "$CAN_PUSH" = "true" ] || fail "token '$LOGIN' does not have push access to $GITHUB_USER/$GITHUB_REPO"
echo "  ✓ Repo: github.com/$GITHUB_USER/$GITHUB_REPO (default branch: $DEFAULT_BRANCH)"

# ── Verify this directory is actually the raddflix-app git repo ──────────────
cd "$WORKSPACE"

if [ ! -d ".git" ]; then
    fail "$WORKSPACE has no .git directory.
     Refusing to run — this script must only ever act on the
     raddflix-app repo root, never on a parent/unrelated workspace."
fi

# Sanity-check this .git actually belongs to raddflix-app, not some other
# repo that happens to share the folder name.
EXISTING_REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$EXISTING_REMOTE" ] && ! printf '%s' "$EXISTING_REMOTE" | grep -qi "$GITHUB_REPO"; then
    fail "existing 'origin' remote ($EXISTING_REMOTE) does not look like
     $GITHUB_USER/$GITHUB_REPO. Refusing to push — this looks like the
     wrong repo. Fix the remote manually if this is intentional."
fi

# ── Detect current branch (never assume 'main' blindly) ──────────────────────
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$CURRENT_BRANCH" ] || [ "$CURRENT_BRANCH" = "HEAD" ]; then
    fail "repo is in a detached HEAD state — check out a branch (e.g. 'git checkout $DEFAULT_BRANCH') before pushing."
fi
if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then
    echo "  ⚠️  Current branch is '$CURRENT_BRANCH', not the default branch '$DEFAULT_BRANCH'."
    echo "     This script will push to '$CURRENT_BRANCH', not '$DEFAULT_BRANCH'."
fi
TARGET_BRANCH="$CURRENT_BRANCH"

# ── Refuse to run with an unresolved merge/rebase in progress ────────────────
if [ -d ".git/rebase-merge" ] || [ -d ".git/rebase-apply" ] || [ -f ".git/MERGE_HEAD" ]; then
    fail "a merge or rebase is already in progress in this repo — resolve it manually first (git status)."
fi

# ── Set git remote (token passed per-request, never persisted to disk) ───────
echo ""
echo "▶ Setting git remote..."

PLAIN_URL="https://github.com/$GITHUB_USER/$GITHUB_REPO.git"
if [ -n "$EXISTING_REMOTE" ]; then
    git remote set-url origin "$PLAIN_URL"
    echo "  ✓ Remote 'origin' set to $PLAIN_URL (no token stored on disk)"
else
    git remote add origin "$PLAIN_URL"
    echo "  ✓ Remote 'origin' added: $PLAIN_URL"
fi

# ── Configure git identity (only if not already set) ─────────────────────────
git config user.email >/dev/null 2>&1 || git config user.email "agent@raddflix.app"
git config user.name  >/dev/null 2>&1 || git config user.name  "RaddFlix Agent"

# ── Stage changes, refusing to commit obvious secrets or conflict markers ────
echo ""
echo "▶ Staging changes..."
git add -A

if git diff --cached --quiet; then
    echo "  ✓ Nothing new to commit — checking if a push is still needed..."
    NOTHING_TO_COMMIT=1
else
    NOTHING_TO_COMMIT=0

    # Guard: unresolved conflict markers in any staged file
    if git diff --cached -U0 | grep -Eq '^\+(<{7}|={7}|>{7})'; then
        fail "staged changes contain unresolved merge-conflict markers (<<<<<<<, =======, >>>>>>>). Fix before pushing."
    fi

    # Guard: accidental secret-looking files (.env, private keys) getting committed
    STAGED_FILES="$(git diff --cached --name-only)"
    SUSPECT_FILES="$(printf '%s\n' "$STAGED_FILES" | grep -Ei '(^|/)\.env($|\.)|id_rsa$|\.pem$|private.*key' || true)"
    if [ -n "$SUSPECT_FILES" ]; then
        fail "refusing to commit — these staged files look like secrets/keys:
$SUSPECT_FILES
     Unstage them (git restore --staged <file>) and add to .gitignore if unintended."
    fi

    echo "  Files to be committed:"
    printf '%s\n' "$STAGED_FILES" | sed 's/^/    - /'
fi

if [ "$DRY_RUN" = "1" ]; then
    echo ""
    echo "  ℹ️  DRY_RUN=1 — stopping before commit/push. No changes were made."
    exit 0
fi

if [ "$NOTHING_TO_COMMIT" = "0" ]; then
    COMMIT_MSG="${1:-RaddFlix update — $(date '+%Y-%m-%d %H:%M')}"
    git commit -m "$COMMIT_MSG"
    echo "  ✓ Committed: $COMMIT_MSG"
fi

# ── Sync with remote before pushing (avoid non-fast-forward failures) ────────
echo ""
echo "▶ Fetching latest from origin..."
if ! git -c http.extraHeader="Authorization: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)" \
    fetch --quiet origin "$TARGET_BRANCH" 2>/tmp/push_to_github_fetch_err.log; then
    # Branch may not exist on remote yet (first push) — that's fine.
    if grep -qi "couldn't find remote ref" /tmp/push_to_github_fetch_err.log; then
        echo "  ✓ Remote branch '$TARGET_BRANCH' does not exist yet — will create it."
    else
        cat /tmp/push_to_github_fetch_err.log >&2
        fail "could not fetch from origin — check network/token permissions."
    fi
fi
rm -f /tmp/push_to_github_fetch_err.log

if git rev-parse --verify --quiet "origin/$TARGET_BRANCH" >/dev/null; then
    AHEAD_BEHIND="$(git rev-list --left-right --count "HEAD...origin/$TARGET_BRANCH" 2>/dev/null || echo "0 0")"
    BEHIND="$(printf '%s' "$AHEAD_BEHIND" | awk '{print $2}')"
    if [ "${BEHIND:-0}" != "0" ]; then
        fail "local branch is $BEHIND commit(s) behind origin/$TARGET_BRANCH.
     Refusing to force-push over remote changes. Run 'git pull --rebase origin $TARGET_BRANCH'
     locally, resolve any conflicts, then re-run this script."
    fi
fi

# ── Push (token passed as a per-request header, never written to .git/config) ─
echo ""
echo "  → Pushing to github.com/$GITHUB_USER/$GITHUB_REPO ($TARGET_BRANCH)..."

set +e
PUSH_OUTPUT="$(git -c http.extraHeader="Authorization: basic $(printf 'x-access-token:%s' "$GITHUB_TOKEN" | base64 -w0)" \
    push origin "HEAD:$TARGET_BRANCH" 2>&1)"
PUSH_STATUS=$?
set -e

echo "$PUSH_OUTPUT" | sed "s/$GITHUB_TOKEN/[TOKEN]/g"

if [ "$PUSH_STATUS" -ne 0 ]; then
    fail "git push failed (see output above). Nothing further was attempted."
fi

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ Pushed to: https://github.com/$GITHUB_USER/$GITHUB_REPO ($TARGET_BRANCH)"
echo ""
echo "  Next: run bash push_to_oracle.sh to deploy to the server"
echo "══════════════════════════════════════════════════════════════"
echo ""
