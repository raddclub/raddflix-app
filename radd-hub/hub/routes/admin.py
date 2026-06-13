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
import subprocess as _subprocess
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


@bp.route("/api/accounts/<int:aid>/logout", methods=["POST"])
@auth.login_required
def admin_account_logout(aid):
    """Clear all JazzDrive session tokens and mark the account inactive."""
    from .. import jazzdrive as jd
    return jsonify(jd.jd_logout_account(aid))


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


@bp.route("/api/schema-health")
@auth.login_required
def schema_health():
    """Return a full schema health report.

    Checks every critical table + column against the live SQLite DB.
    Any MISSING entry indicates a schema drift that will cause bugs in prod.

    Response::

        {
          "ok": true,
          "issue_count": 0,
          "issues": [],
          "checks": {"app_subscriptions.is_active": true, ...},
          "checked_at": 1234567890
        }
    """
    from .. import db as _db
    result = _db.validate_schema()
    status = 200 if result["ok"] else 207  # 207 = partial — some checks failed
    return jsonify(result), status





# ---------------------------------------------------------------------------
# Keepalive Health API — rich per-account status + event log
# ---------------------------------------------------------------------------

@bp.route("/api/keepalive-health", methods=["GET"])
@auth.login_required
def keepalive_health():
    """Rich keepalive status for all accounts with health classification and event log."""
    import time as _t
    try:
        from .. import keepalive as _ka
        status = _ka.get_status()
        events = _ka.get_events(30)
    except Exception as _ke:
        status = {}
        events = []
        log.warning("keepalive_health: could not import keepalive: %s", _ke)

    now      = int(_t.time())
    accounts = db.list_accounts(hide_secrets=False)
    result   = []

    for acct in accounts:
        aid       = acct["id"]
        ka_st     = (status.get("accounts") or {}).get(str(aid), {})
        exp       = acct.get("token_expires_at") or 0
        last_ok   = ka_st.get("last_ok_at")
        fails     = ka_st.get("consecutive_failures", 0)
        err_class = ka_st.get("last_error_class") or ""
        conflict  = ka_st.get("last_conflict_at")
        has_token = bool((acct.get("validation_key") or "").strip())

        # ── Health classification ─────────────────────────────────────────────
        if not has_token:
            health = "not_linked"
        elif err_class == "device_conflict" or (conflict and (now - conflict) < 7200):
            health = "device_conflict"
        elif fails >= 3:
            health = "dead"
        elif fails >= 1 and err_class == "session_expired":
            health = "needs_otp"
        elif fails >= 1:
            health = "degraded"
        elif exp and exp < now:
            health = "expired"
        elif exp and (exp - now) < 21600:   # < 6h
            health = "expiring_soon"
        elif exp and (exp - now) < 86400:   # < 24h
            health = "expiring_today"
        elif last_ok:
            health = "healthy"
        else:
            health = "unknown"

        secs_left = max(0, exp - now) if exp else None

        result.append({
            "id":                   aid,
            "msisdn":               acct["msisdn"],
            "label":                acct.get("label") or "",
            "role":                 acct.get("role", "scan"),
            "is_active":            bool(acct.get("is_active")),
            "health":               health,
            "token_expires_at":     exp or None,
            "secs_until_expiry":    secs_left,
            "last_ok_at":           last_ok,
            "last_fail_at":         ka_st.get("last_fail_at"),
            "last_error":           ka_st.get("last_error"),
            "last_error_class":     err_class,
            "last_conflict_at":     conflict,
            "last_refresh_at":      ka_st.get("last_refresh_at"),
            "consecutive_failures": fails,
            "device_id":            db.setting("JAZZDRIVE_DEVICE_ID") or "",
            "device_name":          db.setting("JAZZDRIVE_DEVICE_NAME") or "",
        })

    # Sort: flix first, then by health severity
    _health_order = {
        "device_conflict": 0, "dead": 1, "needs_otp": 2, "degraded": 3,
        "expired": 4, "expiring_soon": 5, "expiring_today": 6,
        "healthy": 7, "unknown": 8, "not_linked": 9,
    }
    result.sort(key=lambda a: (
        0 if a["role"] == "flix" else 1,
        _health_order.get(a["health"], 99)
    ))

    return jsonify({
        "ok":               True,
        "accounts":         result,
        "events":           events,
        "worker_started_at": status.get("worker_started_at"),
        "now":              now,
        "keepalive_on":     db.setting("KEEPALIVE_ENABLED", "1") == "1",
        "jd_enabled":       db.setting("JAZZDRIVE_ENABLED", "1") == "1",
    })


@bp.route("/api/keepalive-health/trigger/<int:aid>", methods=["POST"])
@auth.login_required
def keepalive_trigger(aid):
    """Trigger an immediate heartbeat for the given account (runs in background thread)."""
    try:
        from .. import keepalive as _ka
        _ka.trigger_heartbeat(aid)
        return jsonify({"ok": True, "message": f"Heartbeat triggered for account {aid}"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

# ─────────────────────────────────────────────────────────────────────────────
# JazzDrive Session — status + force-refresh
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/api/jd-session", methods=["GET"])
@auth.login_required
def jd_session_status():
    """Return current JazzDrive token state from the accounts DB row."""
    import time as _t
    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT id, msisdn, label, jsessionid, refresh_token, raw_accesstoken, "
                "token_expires_at, last_keepalive_at, is_active "
                "FROM accounts WHERE role=\'flix\' AND is_active=1 LIMIT 1"
            ).fetchone()
        if not row:
            return jsonify({"ok": False, "error": "No active flix account found"})
        row = dict(row)
        now  = int(_t.time())
        kpa  = row.get("last_keepalive_at") or 0
        exp  = row.get("token_expires_at") or 0
        return jsonify({
            "ok":                  True,
            "account_id":          row["id"],
            "msisdn":              row["msisdn"],
            "label":               row["label"] or "",
            "has_jsessionid":      bool((row.get("jsessionid")      or "").strip()),
            "has_refresh_token":   bool((row.get("refresh_token")   or "").strip()),
            "has_raw_accesstoken": bool((row.get("raw_accesstoken") or "").strip()),
            "token_expires_at":    exp,
            "token_expired":       bool(exp and exp < now),
            "last_keepalive_at":   kpa or None,
            "is_active":           bool(row["is_active"]),
        })
    except Exception as e:
        log.exception("jd_session_status error")
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/jd-force-refresh", methods=["POST"])
@auth.login_required
def jd_force_refresh():
    """Try to refresh the JazzDrive session using stored tokens.

    Returns {ok, error?, otp_required?}.
    If all silent strategies fail → {ok:false, otp_required:true}.
    """
    try:
        from .. import jazzdrive as _jd
        # Always resolve the active flix account from DB so we use the current
        # DB tokens (not the potentially-stale jazzdrive_session.json file).
        _acct_id = None
        try:
            with db.conn() as _c:
                _r = _c.execute(
                    "SELECT id FROM accounts WHERE role=\'flix\' AND is_active=1 LIMIT 1"
                ).fetchone()
                if _r:
                    _acct_id = _r["id"]
        except Exception:
            pass
        result = _jd.refresh_session(account_id=_acct_id)
        if not result.get("ok"):
            err = result.get("error", "")
            # Detect OTP-required signal from various failure messages
            otp_needed = any(x in err.lower() for x in [
                "otp", "401", "silent login failed", "invalid_grant", "re-login"
            ])
            result["otp_required"] = otp_needed
        return jsonify(result)
    except Exception as e:
        cls = type(e).__name__
        vpn = "JDVPNRequired" in cls
        return jsonify({
            "ok":          False,
            "error":       str(e),
            "vpn_error":   vpn,
            "otp_required": not vpn,
        }), 500


# ---------------------------------------------------------------------------
# Background Services page
# ---------------------------------------------------------------------------

_JD_SERVICE_NAMES = {"keepalive", "scan", "upload", "scheduler"}

_SERVICES = [
    {
        "name":   "jazzdrive_master",
        "label":  "JazzDrive Master Switch",
        "desc":   "Master kill switch for ALL JazzDrive activity — blocks session recovery on startup, keepalive pings, scanning and uploads. Turn OFF when you are done using JazzDrive to protect your Jazz account.",
        "db_key": "JAZZDRIVE_ENABLED",
        "deps":   [],
        "master": True,
    },
    {
        "name":  "keepalive",
        "label": "JazzDrive Keepalive",
        "desc":  "Periodically pings JazzDrive to keep accounts active and tokens fresh.",
        "db_key": "KEEPALIVE_ENABLED",
        "deps":  [],
    },
    {
        "name":  "scan",
        "label": "Scanner",
        "desc":  "Walks JazzDrive folders and indexes new content into the library.",
        "db_key": "SCAN_ENABLED",
        "deps":  ["keepalive"],
    },
    {
        "name":  "upload",
        "label": "Upload Watcher",
        "desc":  "Monitors staging folder and uploads finished encodes to JazzDrive.",
        "db_key": "UPLOAD_ENABLED",
        "deps":  ["keepalive"],
    },
    {
        "name":  "scheduler",
        "label": "Smart Scheduler",
        "desc":  "Generates download deltas and triggers scan/upload on a schedule.",
        "db_key": "SCHEDULER_ENABLED",
        "deps":  ["scan", "upload"],
    },
    {
        "name":  "download",
        "label": "Download Queue",
        "desc":  "Processes the download queue and fetches content from source sites.",
        "db_key": "DOWNLOAD_ENABLED",
        "deps":  [],
    },
    {
        "name":  "mirror",
        "label": "Mirror Retry",
        "desc":  "Re-attempts failed mirrors and syncs library to GitHub / Google Sheets.",
        "db_key": "MIRROR_ENABLED",
        "deps":  [],
    },
    {
        "name":  "domain_doctor",
        "label": "Domain Doctor",
        "desc":  "Auto-discovers working domain URLs for content sources.",
        "db_key": "DOMAIN_DOCTOR_ENABLED",
        "deps":  [],
    },
    {
        "name":      "wa_bot",
        "label":     "WhatsApp Bot",
        "desc":      "WhatsApp chat bot for user requests and status notifications.",
        "db_key":    None,
        "supervisor": "raddflix_wa_bot",
        "deps":      [],
    },
]


def _svc_enabled(svc: dict) -> bool:
    if svc.get("supervisor"):
        try:
            out = _subprocess.check_output(
                ["sudo", "supervisorctl", "status", svc["supervisor"]],
                stderr=_subprocess.DEVNULL, timeout=5,
            ).decode()
            return "RUNNING" in out
        except Exception:
            return False
    return db.setting(svc["db_key"], "1") == "1"


@bp.route("/services")
@auth.login_required
def services_page():
    return render_template("services.html")


@bp.route("/api/services", methods=["GET"])
@auth.login_required
def services_list():
    enabled_map = {s["name"]: _svc_enabled(s) for s in _SERVICES}
    result = []
    for svc in _SERVICES:
        is_on = enabled_map[svc["name"]]
        deps  = svc.get("deps", [])
        missing_deps = [d for d in deps if not enabled_map.get(d, True)] if is_on else []
        broken_rdeps = (
            [s["name"] for s in _SERVICES
             if svc["name"] in s.get("deps", []) and enabled_map.get(s["name"])]
            if not is_on else []
        )
        result.append({
            "name":         svc["name"],
            "label":        svc["label"],
            "desc":         svc["desc"],
            "enabled":      is_on,
            "deps":         deps,
            "missing_deps": missing_deps,
            "broken_rdeps": broken_rdeps,
            "supervisor":   svc.get("supervisor"),
        })
    return jsonify({"ok": True, "services": result})


@bp.route("/api/services/toggle", methods=["POST"])
@auth.login_required
def services_toggle():
    body    = request.get_json(silent=True) or {}
    name    = body.get("service", "").strip()
    enabled = bool(body.get("enabled", True))

    svc = next((s for s in _SERVICES if s["name"] == name), None)
    if not svc:
        return jsonify({"ok": False, "error": f"Unknown service: {name}"}), 404

    auto_enabled: list[str] = []
    warnings:     list[str] = []

    # ── Master kill switch — special handling ─────────────────────────────────
    if name == "jazzdrive_master":
        db.set_setting("JAZZDRIVE_ENABLED", "1" if enabled else "0")
        if not enabled:
            for s in _SERVICES:
                if s["name"] in _JD_SERVICE_NAMES and s.get("db_key"):
                    db.set_setting(s["db_key"], "0")
            log.info("JazzDrive master switch OFF — all JD services disabled")
            return jsonify({
                "ok": True, "auto_enabled": [],
                "warnings": ["All JazzDrive services have been turned OFF. Session recovery on next restart is also blocked."]
            })
        else:
            log.info("JazzDrive master switch ON — JD calls unblocked")
            return jsonify({
                "ok": True, "auto_enabled": [],
                "warnings": ["JazzDrive is now enabled. Turn on individual services (Keepalive etc.) as needed."]
            })

    # Block JD services from enabling while master is OFF
    if name in _JD_SERVICE_NAMES and enabled:
        if db.setting("JAZZDRIVE_ENABLED", "1") != "1":
            return jsonify({"ok": False, "error": "JazzDrive Master Switch is OFF — enable it first."}), 400

    # Auto-enable dependencies first when turning ON
    if enabled:
        enabled_map = {s["name"]: _svc_enabled(s) for s in _SERVICES}
        for dep in svc.get("deps", []):
            if not enabled_map.get(dep):
                dep_svc = next((s for s in _SERVICES if s["name"] == dep), None)
                if dep_svc:
                    if dep_svc.get("supervisor"):
                        try:
                            _subprocess.check_call(
                                ["sudo", "supervisorctl", "start", dep_svc["supervisor"]],
                                timeout=10,
                            )
                        except Exception as e:
                            warnings.append(f"Could not auto-start {dep}: {e}")
                    else:
                        db.set_setting(dep_svc["db_key"], "1")
                    auto_enabled.append(dep)

    # Apply the toggle
    if svc.get("supervisor"):
        cmd = "start" if enabled else "stop"
        try:
            _subprocess.check_call(
                ["sudo", "supervisorctl", cmd, svc["supervisor"]],
                timeout=10,
            )
        except _subprocess.CalledProcessError as e:
            return jsonify({"ok": False, "error": f"supervisorctl {cmd} failed (exit {e.returncode})"}), 500
        except Exception as e:
            return jsonify({"ok": False, "error": str(e)}), 500
    else:
        db.set_setting(svc["db_key"], "1" if enabled else "0")

    # Warn about rdeps that will now be unsatisfied
    if not enabled:
        enabled_map = {s["name"]: _svc_enabled(s) for s in _SERVICES}
        for other in _SERVICES:
            if name in other.get("deps", []) and enabled_map.get(other["name"]):
                warnings.append(f"{other['label']} depends on {svc['label']}")

    return jsonify({"ok": True, "auto_enabled": auto_enabled, "warnings": warnings})
