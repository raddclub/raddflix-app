"""
jazz_keepalive.py — Jazz Drive session keep-alive heartbeat.
The problem this solves
-----------------------
Jazz Drive silently expires sessions somewhere between 2 and 6 hours of
inactivity even though `expires_at` says "valid for 23.5 hours". The web SPA
keeps its own session alive by quietly hitting `/sapi/system/information`
every few minutes; our watcher is mostly idle and does not. So after a
quiet period the next real upload fails with a 401, the user did not know
the session had died, and (worse) `radd_flix.db.session` still claims the
session is healthy because we never actively probed.
This service makes that invisible drift visible:
  1. Every ``HEARTBEAT_MINUTES`` minutes (default 15) it builds a 1 KB
     placeholder file, uploads it to the dedicated folder
     ``Heartbeat/`` on Jazz Drive, then immediately deletes it from the
     remote.
  2. Success path → write ``/tmp/radd_flix_session_alive.json`` with the
     latest heartbeat timestamp.
  3. Failure path → write ``/tmp/radd_flix_session_dead.json`` with the
     reason. The WhatsApp bot watches this file and DMs every admin
     ("Jazz Drive session dead — reply /relogin to wipe and re-pair").
  4. The heartbeat NEVER touches ``radd_flix.db`` or
     ``uploaded_files.json`` so it cannot pollute the catalog.
Usage
-----
  python3 jazz_keepalive.py                # one-shot probe
  python3 jazz_keepalive.py --loop         # run forever, every 15 min
  python3 jazz_keepalive.py --interval 5   # change cadence (minutes)
  python3 jazz_keepalive.py --status       # print last heartbeat result
"""
from __future__ import annotations
import argparse
import json
import logging
import os
import sys
import tempfile
import time
import traceback
from datetime import datetime, timezone
from pathlib import Path
import requests
THIS_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(THIS_DIR))
import radd_flix                                         
log = logging.getLogger("jazz_keepalive")
logging.basicConfig(
    level=os.environ.get("RADD_LOG", "INFO"),
    format="%(asctime)s [%(levelname)s] %(message)s",
)
CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
HEARTBEAT_FOLDER = os.environ.get("RADD_HEARTBEAT_FOLDER", "Heartbeat")
HEARTBEAT_MINUTES_DEFAULT = int(os.environ.get("RADD_HEARTBEAT_MINUTES", "15"))
TMP = Path(tempfile.gettempdir())
ALIVE_FILE = TMP / "radd_flix_session_alive.json"
DEAD_FILE = TMP / "radd_flix_session_dead.json"
def _write_status(path: Path, payload: dict) -> None:
    try:
        path.write_text(json.dumps(payload, indent=2))
    except Exception as exc:                                  
        log.warning("Could not write %s: %s", path.name, exc)
def _clear_status(path: Path) -> None:
    try:
        if path.exists():
            path.unlink()
    except Exception:
        pass
def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")
def _ensure_heartbeat_folder(session, tokens) -> int:
    fid = radd_flix._lookup_folder_id(session, tokens, HEARTBEAT_FOLDER, parent_id=0)
    if fid:
        return int(fid)
    log.info("Creating /%s folder on Jazz Drive ...", HEARTBEAT_FOLDER)
    new_id = radd_flix._create_folder_api(session, tokens, HEARTBEAT_FOLDER, parent_id=0)
    if not new_id:
        raise RuntimeError("_create_folder_api returned no id")
    return int(new_id)
def _delete_remote_file(session, tokens, file_id: int) -> bool:
    auth_qs = radd_flix._auth_params(tokens)
    headers = radd_flix._auth_headers(tokens)
    try:
        url = f"{CLOUD_BASE}/sapi/file?action=delete&{auth_qs}"
        r = session.post(url, json={"data": {"ids": [int(file_id)]}},
                         headers=headers, timeout=20)
        if 200 <= r.status_code < 300:
            return True
    except Exception as exc:
        log.debug("delete POST failed: %s", exc)
    try:
        url = f"{CLOUD_BASE}/sapi/file?action=delete&{auth_qs}&ids={int(file_id)}"
        r = session.get(url, headers=headers, timeout=20)
        return 200 <= r.status_code < 300
    except Exception as exc:
        log.warning("remote delete failed (file_id=%s): %s", file_id, exc)
        return False
def _generate_payload(path: Path) -> int:
    body = (
        f"radd-flix heartbeat probe\n"
        f"generated_at={_now_iso()}\n"
        f"intent=session-liveness-only\n"
        f"do-not-restore=true\n"
        + ("." * 800)
    ).encode("utf-8")
    path.write_bytes(body)
    return len(body)
def heartbeat_once(cfg_path: Path | str = None) -> dict:
    cfg_path = Path(cfg_path or THIS_DIR / "config.json")
    cfg = json.loads(cfg_path.read_text())
    started_at = time.time()
    result: dict = {
        "ok": False,
        "started_at": int(started_at),
        "started_iso": _now_iso(),
        "msisdn": cfg.get("msisdn", ""),
        "folder": HEARTBEAT_FOLDER,
        "duration_ms": 0,
    }
    try:
        session, tokens = radd_flix.get_session(cfg)
    except Exception as exc:
        result["stage"] = "session"
        result["error"] = f"get_session failed: {exc}"
        result["duration_ms"] = int((time.time() - started_at) * 1000)
        _clear_status(ALIVE_FILE)
        _write_status(DEAD_FILE, result)
        return result
    tmp_path = THIS_DIR / f".heartbeat-{int(started_at)}.bin"
    try:
        size = _generate_payload(tmp_path)
        result["payload_bytes"] = size
        folder_id = _ensure_heartbeat_folder(session, tokens)
        result["folder_id"] = folder_id
        t0 = time.time()
        resp = radd_flix.upload_file(
            session, tokens, tmp_path,
            parent_id=folder_id,
            max_retries=2,
        )
        if not isinstance(resp, dict) or not resp.get("id"):
            raise RuntimeError(f"upload returned no file id (got {resp!r})")
        result["upload_file_id"] = int(resp["id"])
        result["upload_ms"] = int((time.time() - t0) * 1000)
        deleted = _delete_remote_file(session, tokens, result["upload_file_id"])
        result["deleted"] = bool(deleted)
        result["ok"] = True
        result["stage"] = "complete"
    except Exception as exc:
        result["stage"] = result.get("stage") or "upload"
        result["error"] = str(exc)
        result["traceback"] = traceback.format_exc(limit=4)
    finally:
        try:
            if tmp_path.exists():
                tmp_path.unlink()
        except Exception:
            pass
    result["duration_ms"] = int((time.time() - started_at) * 1000)
    if result["ok"]:
        _write_status(ALIVE_FILE, result)
        _clear_status(DEAD_FILE)
        log.info("✓ heartbeat ok in %d ms (folder=%s)", result["duration_ms"], HEARTBEAT_FOLDER)
    else:
        _write_status(DEAD_FILE, result)
        _clear_status(ALIVE_FILE)
        log.error("✗ heartbeat FAILED at stage=%s — %s",
                  result["stage"], result.get("error"))
    return result
def loop(interval_minutes: int) -> None:
    backoff = 60
    while True:
        try:
            r = heartbeat_once()
            backoff = 60 if r["ok"] else min(backoff * 2, 600)
        except Exception as exc:
            log.exception("heartbeat raised: %s", exc)
            backoff = min(backoff * 2, 600)
        sleep_s = (interval_minutes * 60) if backoff == 60 else backoff
        log.info("next heartbeat in %d s", sleep_s)
        time.sleep(sleep_s)
def status() -> dict:
    out = {"alive": None, "dead": None}
    if ALIVE_FILE.exists():
        try: out["alive"] = json.loads(ALIVE_FILE.read_text())
        except Exception: pass
    if DEAD_FILE.exists():
        try: out["dead"] = json.loads(DEAD_FILE.read_text())
        except Exception: pass
    return out
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--loop", action="store_true",
                    help="run forever (default: one-shot)")
    ap.add_argument("--interval", type=int, default=HEARTBEAT_MINUTES_DEFAULT,
                    help=f"loop cadence in minutes (default {HEARTBEAT_MINUTES_DEFAULT})")
    ap.add_argument("--status", action="store_true",
                    help="print the last alive/dead status JSON and exit")
    args = ap.parse_args()
    if args.status:
        print(json.dumps(status(), indent=2))
        return 0
    if args.loop:
        log.info("Starting Jazz Drive keep-alive loop (every %d min)", args.interval)
        loop(args.interval)
        return 0
    r = heartbeat_once()
    print(json.dumps(r, indent=2))
    return 0 if r.get("ok") else 1
if __name__ == "__main__":
    sys.exit(main())