"""Admin panel — user management, WhatsApp bot user control, quota management.

Ported all missing endpoints from v2.0's gui_app.py:
  - /admin/api/users             — list all bot users (from bot.db)
  - /admin/api/users/add         — add user to a role
  - /admin/api/users/remove      — remove user from a role
  - /admin/api/quota             — set per-user daily quota
  - /admin/api/accounts          — list hub accounts
  - /admin/api/settings          — bot users.json settings
  - /admin/api/qr                — WhatsApp QR / pairing state
  - /admin/api/qr.png            — WhatsApp QR image
  - /admin/api/cmd               — send admin command to WhatsApp bot
  - /admin/api/get-pairing-number
  - /admin/api/set-pairing-number
  - /admin/api/request-pairing-code
  - /admin/api/relink
  - /admin/api/change-password
"""
from __future__ import annotations
import json
import logging
import time
import uuid as _uuid
from pathlib import Path
from flask import Blueprint, render_template, request, jsonify, redirect, url_for, send_file
from .. import db, auth, config

log = logging.getLogger("hub.admin")

bp = Blueprint("admin", __name__)

# ---------------------------------------------------------------------------
# Bot filesystem paths — must match hub/bots/whatsapp.py V2_BOT_DIR exactly
# ---------------------------------------------------------------------------

try:
    from ..bots.whatsapp import V2_BOT_DIR as _BOT_DIR
    _BOT_DIR = _BOT_DIR.resolve()
except Exception:
    # Fallback: same derivation as hub/bots/whatsapp.py
    _BOT_DIR = (config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "whatsapp-bot").resolve()

_BOT_USERS  = _BOT_DIR / "users.json"
_BOT_QR     = _BOT_DIR / "whatsapp-qr.png"
_BOT_STATE  = _BOT_DIR / "bot-state.json"
_BOT_RELINK = _BOT_DIR / ".relink"


def _read_bot_users() -> dict:
    try:
        return json.loads(_BOT_USERS.read_text())
    except Exception:
        return {"admins": [], "verified": [], "blocked": [], "settings": {}}


def _write_bot_users(d: dict) -> None:
    _BOT_DIR.mkdir(parents=True, exist_ok=True)
    _BOT_USERS.write_text(json.dumps(d, indent=2))


def _norm_num(s) -> str:
    return "".join(c for c in str(s or "") if c.isdigit())


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@bp.route("/")
@auth.login_required
def page():
    return render_template("admin.html",
                           admin_user=config.get_env("RADD_ADMIN_USER", "admin"))


# ---------------------------------------------------------------------------
# Password change
# ---------------------------------------------------------------------------

@bp.route("/api/change-password", methods=["POST"])
@auth.login_required
def change_pw():
    data   = request.get_json(force=True, silent=True) or request.form
    new_pw = (data.get("password") or "").strip()
    if len(new_pw) < 6:
        return jsonify({"error": "Password must be at least 6 characters"}), 400
    config.write_env({"RADD_ADMIN_PASS": new_pw})
    return jsonify({"ok": True})


# ---------------------------------------------------------------------------
# Hub users (DB)
# ---------------------------------------------------------------------------

@bp.route("/api/users")
@auth.login_required
def list_hub_users():
    with db.conn() as c:
        return jsonify([dict(r) for r in c.execute(
            "SELECT * FROM users ORDER BY id"
        ).fetchall()])


# ---------------------------------------------------------------------------
# Bot users.json settings
# ---------------------------------------------------------------------------

@bp.route("/api/settings", methods=["GET"])
@auth.login_required
def bot_settings_get():
    return jsonify(_read_bot_users())


@bp.route("/api/settings", methods=["POST"])
@auth.login_required
def bot_settings_post():
    body = request.get_json(silent=True) or {}
    new_settings = body.get("settings") or {}
    if not isinstance(new_settings, dict):
        return jsonify({"ok": False, "error": "settings must be an object"}), 400
    u = _read_bot_users()
    u["settings"] = {**(u.get("settings") or {}), **new_settings}
    try:
        _write_bot_users(u)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Bot user role management
# ---------------------------------------------------------------------------

@bp.route("/api/users/add", methods=["POST"])
@auth.login_required
def bot_users_add():
    body = request.get_json(silent=True) or {}
    role = body.get("role")
    num  = _norm_num(body.get("number"))
    if role not in ("admins", "verified", "blocked") or not num:
        return jsonify({"ok": False, "error": "bad role or number"}), 400
    u   = _read_bot_users()
    arr = u.setdefault(role, [])
    jid = f"{num}@s.whatsapp.net"
    if not any(_norm_num(x) == num for x in arr):
        arr.append(jid)
    if role == "verified":
        u["blocked"] = [x for x in u.get("blocked", []) if _norm_num(x) != num]
    try:
        _write_bot_users(u)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/users/remove", methods=["POST"])
@auth.login_required
def bot_users_remove():
    body = request.get_json(silent=True) or {}
    role = body.get("role")
    num  = _norm_num(body.get("number"))
    if role not in ("admins", "verified", "blocked") or not num:
        return jsonify({"ok": False, "error": "bad role or number"}), 400
    u = _read_bot_users()
    u[role] = [x for x in u.get(role, []) if _norm_num(x) != num]
    try:
        _write_bot_users(u)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Bot.db user list (from WhatsApp bot's SQLite)
# ---------------------------------------------------------------------------

@bp.route("/api/bot-users", methods=["GET"])
@auth.login_required
def bot_db_users():
    bot_db_path = _BOT_DIR / "bot.db"
    if not bot_db_path.exists():
        return jsonify({"users": [],
                        "warning": "bot.db not found — start the bot once first"})
    try:
        import sqlite3 as _sqlite
        with _sqlite.connect(str(bot_db_path)) as conn:
            conn.row_factory = _sqlite.Row
            rows = conn.execute(
                "SELECT jid, role, daily_quota_mb, used_today_mb, "
                "       quota_reset_date, points, referrer_jid, referral_code, "
                "       pushname, joined_at, last_seen_at "
                "FROM bot_users "
                "ORDER BY (CASE role WHEN 'admin' THEN 0 WHEN 'verified' THEN 1 "
                "                    WHEN 'free' THEN 2 ELSE 3 END), "
                "         last_seen_at DESC"
            ).fetchall()
        return jsonify({"users": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"users": [], "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Quota management
# ---------------------------------------------------------------------------

@bp.route("/api/quota", methods=["POST"])
@auth.login_required
def admin_set_quota():
    body = request.get_json(silent=True) or {}
    num  = _norm_num(body.get("number"))
    mb   = body.get("mb")
    try:
        mb = max(0, int(mb))
    except Exception:
        return jsonify({"ok": False, "error": "mb must be a non-negative integer"}), 400
    if not num:
        return jsonify({"ok": False, "error": "number required"}), 400
    bot_db_path = _BOT_DIR / "bot.db"
    if not bot_db_path.exists():
        return jsonify({"ok": False, "error": "bot.db not found"}), 404
    try:
        import sqlite3 as _sqlite
        jid = f"{num}@s.whatsapp.net"
        with _sqlite.connect(str(bot_db_path)) as conn:
            conn.execute(
                "INSERT INTO bot_users (jid, daily_quota_mb) VALUES (?, ?) "
                "ON CONFLICT(jid) DO UPDATE SET daily_quota_mb = excluded.daily_quota_mb",
                (jid, mb),
            )
            conn.execute(
                "INSERT INTO bot_audit (ts, jid, event, detail) VALUES (?, ?, 'admin.quota.web', ?)",
                (int(time.time()), jid, f"set to {mb} MB/day via admin panel"),
            )
        return jsonify({"ok": True, "jid": jid, "daily_quota_mb": mb})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Hub accounts
# ---------------------------------------------------------------------------

@bp.route("/api/accounts", methods=["GET"])
@auth.login_required
def admin_accounts_list():
    try:
        rows = db.list_accounts()
        return jsonify({"accounts": rows})
    except Exception as e:
        return jsonify({"accounts": [], "error": str(e)}), 500


# ---------------------------------------------------------------------------
# WhatsApp QR / pairing
# ---------------------------------------------------------------------------

@bp.route("/api/qr")
@auth.login_required
def admin_qr_status():
    state = {
        "connected": False, "bot_number": "", "qr_available": False,
        "pairing_code": None, "pairing_number": None, "library_total": 0,
    }
    try:
        if _BOT_STATE.exists():
            d = json.loads(_BOT_STATE.read_text())
            state["connected"]     = bool(d.get("connected"))
            state["bot_number"]    = d.get("bot_number", "")
            state["pairing_code"]  = d.get("pairing_code")
            state["pairing_number"]= d.get("pairing_number")
            state["library_total"] = d.get("library_total", 0)
            if time.time() - float(d.get("ts", 0)) > 30:
                state["connected"] = False
    except Exception:
        pass
    state["qr_available"] = _BOT_QR.exists()
    return jsonify(state)


@bp.route("/api/qr.png")
@auth.login_required
def admin_qr_png():
    if not _BOT_QR.exists():
        return ("", 404)
    return send_file(str(_BOT_QR), mimetype="image/png", max_age=0)


@bp.route("/api/get-pairing-number", methods=["GET"])
@auth.login_required
def admin_get_pairing_number():
    try:
        num = (_BOT_DIR / "pairing-number.txt").read_text().strip()
        return jsonify({"ok": True, "number": num})
    except Exception:
        return jsonify({"ok": True, "number": ""})


@bp.route("/api/set-pairing-number", methods=["POST"])
@auth.login_required
def admin_set_pairing_number():
    body = request.get_json(silent=True) or {}
    num  = _norm_num(body.get("number", ""))
    if num.startswith("03") and len(num) == 11:
        num = "92" + num[1:]
    if len(num) < 10:
        return jsonify({
            "ok": False,
            "error": "Phone number too short — use international format e.g. 923xxxxxxxxx"
        }), 400
    try:
        _BOT_DIR.mkdir(parents=True, exist_ok=True)
        (_BOT_DIR / "pairing-number.txt").write_text(num)
        return jsonify({"ok": True, "number": num})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/request-pairing-code", methods=["POST"])
@auth.login_required
def admin_request_pairing_code():
    try:
        _BOT_DIR.mkdir(parents=True, exist_ok=True)
        (_BOT_DIR / ".pairing-request").write_text(str(int(time.time())))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/relink", methods=["POST"])
@auth.login_required
def admin_relink():
    try:
        _BOT_DIR.mkdir(parents=True, exist_ok=True)
        _BOT_RELINK.write_text(str(int(time.time())))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Bot command passthrough
# ---------------------------------------------------------------------------

@bp.route("/api/cmd", methods=["POST"])
@auth.login_required
def admin_cmd():
    """Send an admin command to the WhatsApp bot process via temp files."""
    import tempfile
    data = request.get_json(silent=True) or {}
    cmd  = (data.get("cmd") or "").strip()
    if not cmd:
        return jsonify({"ok": False, "error": "missing cmd"}), 400

    _BOT_CMD_DIR = Path(tempfile.gettempdir()) / "radd_bot_cmd"
    _BOT_CMD_DIR.mkdir(exist_ok=True, parents=True)

    # Check if bot is alive
    bot_alive = False
    try:
        if _BOT_STATE.exists():
            d = json.loads(_BOT_STATE.read_text())
            bot_alive = (time.time() - float(d.get("ts", 0))) < 30
    except Exception:
        pass

    if not bot_alive:
        return jsonify({
            "ok": False,
            "error": "WhatsApp bot is offline — start it (or scan its QR) from the admin panel first."
        }), 503

    rid      = _uuid.uuid4().hex[:12]
    in_path  = _BOT_CMD_DIR / f"{rid}.in.json"
    out_path = _BOT_CMD_DIR / f"{rid}.out.json"

    try:
        in_path.write_text(json.dumps({
            "id": rid, "cmd": cmd,
            "from": "web-admin", "ts": int(time.time()),
        }))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

    deadline = time.time() + 12.0
    while time.time() < deadline:
        if out_path.exists():
            try:
                resp = json.loads(out_path.read_text())
            except Exception as parse_err:
                try: out_path.unlink()
                except Exception: pass
                return jsonify({"ok": False, "error": f"Bad response from bot: {parse_err}"}), 500
            finally:
                try: out_path.unlink()
                except Exception: pass
            return jsonify({
                "ok": True,
                "lines": resp.get("lines", []),
                "took_ms": int((time.time() - resp.get("ts", time.time())) * 1000),
            })
        time.sleep(0.25)

    try: in_path.unlink()
    except Exception: pass
    return jsonify({
        "ok": False,
        "error": "Bot did not respond within 12 s. It may be reconnecting — try again.",
    }), 504


# ---------------------------------------------------------------------------
# Database management — reset, sync, pull
# ---------------------------------------------------------------------------

@bp.route("/api/db/reset", methods=["POST"])
@auth.login_required
def db_reset():
    """Clear catalog tables and bump version so Flutter devices re-sync.

    Uses a direct sqlite3 connection with isolation_level=None (manual transaction
    control) so Python's implicit transaction manager never conflicts with our
    BEGIN IMMEDIATE. A wal_checkpoint(TRUNCATE) is issued after commit so the WAL
    is flushed immediately and the change is visible to every new connection.
    FTS index is rebuilt after clearing titles so orphaned tombstones are removed.
    """
    import time as _time
    import sqlite3 as _sqlite3
    RESET_TABLES = [
        "files", "titles", "mirror_log", "scan_log", "queue",
        "bot_status_index", "turbo_cache", "recommendation_cache", "media_index",
    ]
    cleared, skipped, row_counts = [], [], {}
    try:
        db_path = str(config.DB_PATH)
        # isolation_level=None = autocommit/manual mode — prevents Python sqlite3
        # from auto-issuing BEGIN that would conflict with BEGIN IMMEDIATE below.
        con = _sqlite3.connect(db_path, timeout=30, check_same_thread=False,
                               isolation_level=None)
        try:
            con.execute("PRAGMA foreign_keys = OFF")
            con.execute("BEGIN IMMEDIATE")
            for tbl in RESET_TABLES:
                try:
                    cur = con.execute(f"DELETE FROM {tbl}")
                    cleared.append(tbl)
                    row_counts[tbl] = cur.rowcount
                except Exception:
                    skipped.append(tbl)
            for tbl in RESET_TABLES:
                try:
                    con.execute("DELETE FROM sqlite_sequence WHERE name=?", (tbl,))
                except Exception:
                    pass
            # Rebuild FTS index so orphaned tombstones from the deleted titles
            # are fully removed (not just soft-deleted in titles_fts_data).
            try:
                con.execute("INSERT INTO titles_fts(titles_fts) VALUES(\'rebuild\')")
            except Exception:
                pass
            con.execute("COMMIT")
            con.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        except Exception:
            try:
                con.execute("ROLLBACK")
            except Exception:
                pass
            raise
        finally:
            try:
                con.execute("PRAGMA foreign_keys = ON")
            except Exception:
                pass
            con.close()
        # Bump catalog version so every Flutter device re-syncs on next launch
        db.set_setting("catalog_forced_version", str(int(_time.time())))
        titles_n = row_counts.get("titles", 0)
        files_n  = row_counts.get("files",  0)
        return jsonify({
            "ok": True,
            "message": f"Cleared {titles_n} title(s) and {files_n} file(s). Devices will re-sync on next launch.",
            "cleared": cleared,
            "skipped": skipped,
            "row_counts": row_counts,
        })
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/restore", methods=["POST"])
@auth.login_required
def db_restore():
    """Trigger a JazzDrive re-scan for all accounts to rebuild the catalog.
    Safe to call after a db/reset. Launches background scans and returns
    immediately. Check /scan/ page for live progress.
    """
    try:
        from .. import scanner as _scan
        accounts = db.list_accounts()
        started, skipped, errors = [], [], []
        for a in accounts:
            aid = a["id"]
            if not a.get("token_expires_at"):
                skipped.append({"id": aid, "msisdn": a.get("msisdn", ""),
                                 "reason": "no active session"})
                continue
            r = _scan.start_scan(aid)
            if r.get("ok"):
                started.append({"id": aid, "msisdn": a.get("msisdn", "")})
            elif "already running" in (r.get("error") or "").lower():
                skipped.append({"id": aid, "msisdn": a.get("msisdn", ""),
                                 "reason": "already running"})
            else:
                errors.append({"id": aid, "msisdn": a.get("msisdn", ""),
                                "error": r.get("error")})
        n = len(started)
        return jsonify({
            "ok": True,
            "started": started,
            "skipped": skipped,
            "errors":  errors,
            "message": (f"Restore started: {n} scan(s) launched"
                        + (f", {len(skipped)} skipped" if skipped else "")
                        + (f", {len(errors)} error(s)" if errors else "") + "."),
        })
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/sync", methods=["POST"])
@auth.login_required
def db_sync():
    """Push full local DB to GitHub + Google Sheets."""
    from .. import sync as _sync
    data = request.get_json(silent=True) or {}
    mode = data.get("mode", "both")
    try:
        result = _sync.sync_all(mode=mode)
        return jsonify({"ok": True, **result})
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/pull", methods=["POST"])
@auth.login_required
def db_pull():
    """Pull missing records from GitHub into local DB."""
    from .. import sync as _sync
    try:
        result = _sync.pull_from_github()
        return jsonify(result)
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/clear-github", methods=["POST"])
@auth.login_required
def db_clear_github():
    """Replace GitHub JSON with empty object."""
    from .. import sync as _sync
    try:
        result = _sync.clear_github_db()
        return jsonify(result)
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/clear-gsheets", methods=["POST"])
@auth.login_required
def db_clear_gsheets():
    """Clear all rows from Google Sheet."""
    from .. import sync as _sync
    try:
        result = _sync.clear_gsheets_db()
        return jsonify(result)
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


@bp.route("/api/db/full-delete", methods=["POST"])
@auth.login_required
def db_full_delete():
    """Wipe the local SQLite database file and re-initialize it."""
    import os
    try:
        db_path = config.DB_PATH
        if db_path.exists():
            # Delete the main DB and its journal files
            for suffix in ["", "-wal", "-shm"]:
                p = Path(str(db_path) + suffix)
                if p.exists():
                    p.unlink()
        
        # Re-initialize to create a fresh empty structure
        from ..db import init_db
        init_db()
        
        return jsonify({"ok": True, "message": "Database file wiped and re-initialized"})
    except Exception as exc:
        return jsonify({"ok": False, "error": str(exc)}), 500


# ---------------------------------------------------------------------------
# Domain Doctor — on-demand trigger
# ---------------------------------------------------------------------------

@bp.route("/api/domain-doctor/run", methods=["POST"])
@auth.login_required
def domain_doctor_run():
    """Trigger a domain discovery cycle right now (runs in background thread)."""
    import threading as _threading
    from .. import domain_doctor as _dd

    site = (request.get_json(force=True, silent=True) or {}).get("site")

    def _run():
        try:
            if site:
                _dd.probe_site(site)
            else:
                _dd.probe_all()
        except Exception as exc:
            log.warning("domain_doctor on-demand error: %s", exc)

    _threading.Thread(target=_run, daemon=True, name="domain-doctor-ondemand").start()
    msg = f"Domain discovery started for '{site}'" if site else "Full domain discovery cycle started"
    return jsonify({"ok": True, "message": msg})


@bp.route("/api/domain-doctor/status", methods=["GET"])
@auth.login_required
def domain_doctor_status():
    """Return current cached domain health for all sites."""
    from .. import domain_doctor as _dd, db as _db
    health = _dd.get_domain_health()
    # Enrich with stored DB domains
    for site in _dd.MIRROR_REGISTRY:
        key = f"domain_{site}"
        stored = _db.setting(key, "")
        ts = _db.setting(f"{key}_ts", "")
        if site not in health:
            health[site] = {}
        health[site]["stored_domain"] = stored
        health[site]["stored_at"] = int(ts) if ts else None
    return jsonify({"ok": True, "sites": health})


# ---------------------------------------------------------------------------
# Scheduler — on-demand trigger
# ---------------------------------------------------------------------------

@bp.route("/api/scheduler/run", methods=["POST"])
@auth.login_required
def scheduler_run():
    """Trigger the ongoing-series rescan right now (runs in background thread)."""
    import threading as _threading
    from .. import scheduler as _sched

    def _run():
        try:
            _sched.rescan_ongoing_titles()
        except Exception as exc:
            log.warning("scheduler on-demand error: %s", exc)

    _threading.Thread(target=_run, daemon=True, name="scheduler-ondemand").start()
    return jsonify({"ok": True, "message": "Ongoing series rescan started"})


# ---------------------------------------------------------------------------
# Re-import -- patch files.filename for an account without a full re-scan
# ---------------------------------------------------------------------------

_reimport_jobs: dict = {}  # job_id -> {status, files_updated, error, started_at, finished_at}


@bp.route("/api/admin/reimport", methods=["POST"])
@auth.login_required
def admin_reimport_start():
    """Trigger _import_legacy_into_v3_for_account() for one account.
    Re-runs the TMDB-clean filename logic on every file row without
    touching JazzDrive or doing a new network scan.
    Body: {"account_id": <int>}
    Returns: {"ok": true, "job_id": "..."}  poll GET /api/admin/reimport/<job_id>
    """
    import threading as _threading
    import uuid as _uuid_mod
    import time as _time

    body = request.get_json(force=True, silent=True) or {}
    account_id = body.get("account_id")
    if not account_id:
        return jsonify({"ok": False, "error": "account_id required"}), 400
    try:
        account_id = int(account_id)
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "account_id must be an integer"}), 400

    acct = db.get_account(account_id)
    if not acct:
        return jsonify({"ok": False, "error": f"account {account_id} not found"}), 404

    job_id = _uuid_mod.uuid4().hex[:12]
    _reimport_jobs[job_id] = {
        "status": "running",
        "account_id": account_id,
        "msisdn": acct.get("msisdn", ""),
        "files_updated": 0,
        "error": None,
        "started_at": int(_time.time()),
        "finished_at": None,
    }

    def _run():
        import time as _t
        try:
            from ..scanner import _ensure_legacy_account, _import_legacy_into_v3_for_account
            legacy_id = _ensure_legacy_account(account_id)
            n = _import_legacy_into_v3_for_account(legacy_id, account_id)
            _reimport_jobs[job_id].update({
                "status": "done",
                "files_updated": n,
                "finished_at": int(_t.time()),
            })
            log.info("reimport job %s done -- %d files updated for account %d", job_id, n, account_id)
        except Exception as exc:
            _reimport_jobs[job_id].update({
                "status": "error",
                "error": str(exc),
                "finished_at": int(_t.time()),
            })
            log.warning("reimport job %s failed for account %d: %s", job_id, account_id, exc)

    _threading.Thread(target=_run, daemon=True, name=f"reimport-{job_id}").start()
    return jsonify({
        "ok": True,
        "job_id": job_id,
        "account_id": account_id,
        "msisdn": acct.get("msisdn", ""),
        "message": f"Re-import started for account {account_id}. Poll GET /api/admin/reimport/{job_id} for result.",
    })


@bp.route("/api/admin/reimport/<job_id>", methods=["GET"])
@auth.login_required
def admin_reimport_status(job_id: str):
    """Poll the result of a reimport job started by POST /api/admin/reimport."""
    job = _reimport_jobs.get(job_id)
    if not job:
        return jsonify({"ok": False, "error": f"job {job_id} not found (expires on server restart)"}), 404
    return jsonify({"ok": True, **job})
