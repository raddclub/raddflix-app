import json
import base64
import logging
import os
import threading
import requests
log = logging.getLogger("RaddFlix.GitHub")
GITHUB_API = "https://api.github.com"
_github_lock = threading.Lock()


def _get_config():
    token  = os.environ.get("GITHUB_TOKEN", "")
    repo   = os.environ.get("GITHUB_REPO", "")
    path   = os.environ.get("GITHUB_DB_PATH", "")
    branch = os.environ.get("GITHUB_BRANCH", "")
    if not token or not repo:
        try:
            cfg_path = os.path.join(os.path.dirname(__file__), "config.json")
            with open(cfg_path) as f:
                cfg = json.load(f)
            token  = token  or cfg.get("github_token", "")
            repo   = repo   or cfg.get("github_repo", "")
            path   = path   or cfg.get("github_db_path", "")
            branch = branch or cfg.get("github_branch", "")
        except Exception:
            pass
    return token, repo, path or "uploaded_files.json", branch or "main"


def _headers(token):
    return {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


def _get_file_sha(token, repo, path, branch):
    url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
    r = requests.get(url, headers=_headers(token), params={"ref": branch}, timeout=15)
    if r.status_code == 200:
        return r.json().get("sha")
    return None


def _read_db_json(token, repo, path, branch) -> dict:
    """Fetch and decode the current uploaded_files.json from GitHub. Returns {} on any error."""
    url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
    try:
        r = requests.get(url, headers=_headers(token), params={"ref": branch}, timeout=15)
        if r.status_code == 200:
            content_b64 = r.json().get("content", "")
            raw = base64.b64decode(content_b64.replace("\n", "")).decode("utf-8")
            return json.loads(raw)
    except Exception as exc:
        log.debug("_read_db_json: %s", exc)
    return {}


def push_db(db: dict, max_attempts: int = 3) -> bool:
    """Write the full library dict to uploaded_files.json on GitHub."""
    token, repo, path, branch = _get_config()
    if not token or not repo:
        log.debug("GitHub sync skipped — GITHUB_TOKEN or GITHUB_REPO not set.")
        return False
    with _github_lock:
        for attempt in range(1, max_attempts + 1):
            try:
                content = json.dumps(db, indent=2, default=str)
                encoded = base64.b64encode(content.encode("utf-8")).decode("utf-8")
                sha = _get_file_sha(token, repo, path, branch)
                url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
                payload = {
                    "message": f"Auto-update: {len(db)} file(s) in database",
                    "content": encoded,
                    "branch": branch,
                }
                if sha:
                    payload["sha"] = sha
                r = requests.put(url, headers=_headers(token), json=payload, timeout=30)
                if r.status_code in (200, 201):
                    log.info("GitHub DB synced: %d records → %s/%s", len(db), repo, path)
                    return True
                elif r.status_code == 409:
                    log.warning(
                        "GitHub sync 409 conflict on attempt %d/%d — "
                        "re-fetching SHA and retrying ...", attempt, max_attempts)
                    continue
                else:
                    log.error("GitHub sync failed: HTTP %s — %s", r.status_code, r.text[:200])
                    return False
            except Exception as exc:
                log.error("GitHub sync error: %s", exc)
                return False
    log.error("GitHub sync failed after %d attempts (persistent 409 conflict).", max_attempts)
    return False


def push_merged_entry(file_id: str, entry: dict, max_attempts: int = 3) -> bool:
    """Merge a single file entry into uploaded_files.json on GitHub.

    Reads the current uploaded_files.json, adds/updates the entry keyed by
    file_id, then writes the merged result back.  This replaces the old
    push_single_entry approach that created a separate /uploads/{id}.json file
    for every upload (redundant and polluting the repo).
    """
    token, repo, path, branch = _get_config()
    if not token or not repo:
        return False
    with _github_lock:
        for attempt in range(1, max_attempts + 1):
            try:
                current = _read_db_json(token, repo, path, branch)
                current[str(file_id)] = entry
                content = json.dumps(current, indent=2, default=str)
                encoded = base64.b64encode(content.encode("utf-8")).decode("utf-8")
                sha = _get_file_sha(token, repo, path, branch)
                url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
                payload = {
                    "message": f"Upload: file {file_id} added",
                    "content": encoded,
                    "branch": branch,
                }
                if sha:
                    payload["sha"] = sha
                r = requests.put(url, headers=_headers(token), json=payload, timeout=30)
                if r.status_code in (200, 201):
                    log.info("GitHub: merged file %s into %s/%s", file_id, repo, path)
                    return True
                elif r.status_code == 409:
                    log.warning(
                        "GitHub merge 409 on attempt %d/%d — retrying ...", attempt, max_attempts)
                    continue
                else:
                    log.error("GitHub merge failed: HTTP %s — %s", r.status_code, r.text[:200])
                    return False
            except Exception as exc:
                log.error("GitHub merge error: %s", exc)
                return False
    log.error("GitHub merge failed after %d attempts.", max_attempts)
    return False


def delete_file(path: str, sha: str, message: str = "Remove file") -> bool:
    """Delete a single file from the GitHub repo by path + SHA."""
    token, repo, _, branch = _get_config()
    if not token or not repo:
        return False
    url = f"{GITHUB_API}/repos/{repo}/contents/{path}"
    try:
        r = requests.delete(
            url,
            headers=_headers(token),
            json={"message": message, "sha": sha, "branch": branch},
            timeout=20,
        )
        if r.status_code in (200, 204):
            log.info("GitHub: deleted %s", path)
            return True
        log.warning("GitHub delete %s: HTTP %s", path, r.status_code)
        return False
    except Exception as exc:
        log.error("GitHub delete error for %s: %s", path, exc)
        return False
