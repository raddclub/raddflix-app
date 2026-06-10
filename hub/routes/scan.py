"""JD Indexer — scan multiple JazzDrive accounts to build the media library DB."""
import json as _json
import time as _time
from flask import Blueprint, render_template, request, jsonify, Response, stream_with_context
from .. import db, auth, scanner as scan_mod

bp = Blueprint("scan", __name__)


@bp.route("/")
@auth.login_required
def page():
    flix_accounts = db.list_accounts(role="flix")
    flix_msisdn = flix_accounts[0]["msisdn"] if flix_accounts else None
    return render_template("scan.html",
        accounts=db.list_accounts(),
        stats=db.count_library(),
        flix_msisdn=flix_msisdn,
        scan_enabled=(db.setting("SCAN_ENABLED", "1") == "1"))


@bp.route("/api/accounts", methods=["GET"])
@auth.login_required
def list_accts():
    return jsonify(db.list_accounts())


@bp.route("/api/accounts", methods=["POST"])
@auth.login_required
def add_acct():
    data = request.get_json(force=True, silent=True) or request.form
    msisdn = db.normalize_msisdn(data.get("msisdn"))
    label  = (data.get("label")  or "").strip()
    notes  = (data.get("notes")  or "").strip()
    if not msisdn:
        return jsonify({"error": "msisdn required"}), 400
    try:
        aid = db.upsert_account(msisdn=msisdn, label=label, notes=notes, role="scan")
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 409
    return jsonify({"ok": True, "id": aid})


@bp.route("/api/accounts/<int:aid>", methods=["DELETE"])
@auth.login_required
def del_acct(aid):
    db.delete_account(aid)
    return jsonify({"ok": True})


@bp.route("/api/accounts/<int:aid>/send-otp", methods=["POST"])
@auth.login_required
def send_otp(aid):
    return jsonify(scan_mod.send_otp(aid))


@bp.route("/api/accounts/<int:aid>/resend-otp", methods=["POST"])
@auth.login_required
def resend_otp(aid):
    return jsonify(scan_mod.resend_otp(aid))


@bp.route("/api/accounts/<int:aid>/verify-otp", methods=["POST"])
@auth.login_required
def verify_otp(aid):
    data = request.get_json(force=True, silent=True) or request.form
    otp = (data.get("otp") or "").strip()
    if not otp:
        return jsonify({"ok": False, "error": "otp required"}), 400
    return jsonify(scan_mod.verify_otp(aid, otp))



@bp.route("/api/accounts/<int:aid>/refresh-session", methods=["POST"])
@auth.login_required
def refresh_session(aid):
    """Silently renew the JazzDrive access token using the stored refresh_token.

    No OTP required — mirrors what the Jazz Drive Android app does to stay
    logged in for months. Returns {"ok": true} on success, {"ok": false, "error": ...}
    if no refresh_token is stored or the refresh call fails.
    """
    from .. import jazzdrive as jd
    return jsonify(jd.refresh_session(account_id=aid))


@bp.route("/api/accounts/<int:aid>/scan", methods=["POST"])
@auth.login_required
def scan(aid):
    if db.setting("SCAN_ENABLED", "1") != "1":
        return jsonify({"ok": False, "error": "Scan is currently disabled — enable it in Settings → Services."}), 503
    return jsonify(scan_mod.start_scan(aid))


@bp.route("/api/accounts/<int:aid>/scan/pause", methods=["POST"])
@auth.login_required
def pause_scan(aid):
    return jsonify(scan_mod.pause_scan(aid))


@bp.route("/api/accounts/<int:aid>/scan/resume", methods=["POST"])
@auth.login_required
def resume_scan(aid):
    return jsonify(scan_mod.resume_scan(aid))


@bp.route("/api/accounts/<int:aid>/scan/stop", methods=["POST"])
@auth.login_required
def stop_scan(aid):
    return jsonify(scan_mod.stop_scan(aid))


@bp.route("/api/accounts/<int:aid>/scan/stream")
@auth.login_required
def scan_stream(aid):
    """SSE endpoint — streams scan log entries in real-time as they are written.

    Yields ``data: <json>`` lines where the JSON is one of:
      {"type": "log",  "kind": "...", "message": "...", "id": N}
      {"type": "done", "files_seen": N}

    The stream closes once the scan finishes (or after 2 h).
    """
    def _gen():
        last_id   = 0
        deadline  = _time.time() + 7200
        idle_tick = 0

        while _time.time() < deadline:
            entries = db.get_scan_log(aid, after=last_id) or []
            for entry in entries:
                eid = entry.get("id") or 0
                if isinstance(eid, int) and eid > last_id:
                    last_id = eid
                payload = _json.dumps({
                    "type":    "log",
                    "kind":    entry.get("kind", "info"),
                    "message": entry.get("message", ""),
                    "id":      eid,
                })
                yield f"data: {payload}\n\n"
                idle_tick = 0

            prog = scan_mod.scan_progress(aid)
            if not prog.get("running"):
                yield f"data: {_json.dumps({'type': 'done', 'files_seen': prog.get('files_seen', 0)})}\n\n"
                return

            idle_tick += 1
            if idle_tick >= 2:
                yield ": heartbeat\n\n"
                idle_tick = 0
            _time.sleep(0.4)

    return Response(
        stream_with_context(_gen()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


@bp.route("/api/accounts/<int:aid>/progress")
@auth.login_required
def progress(aid):
    return jsonify(scan_mod.scan_progress(aid))


@bp.route("/api/accounts/<int:aid>/log")
@auth.login_required
def acct_log(aid):
    after = int(request.args.get("after", 0))
    return jsonify(db.get_scan_log(aid, after=after))


@bp.route("/api/files")
@auth.login_required
def all_files():
    """Return all indexed files from the local DB (up to 10 000 rows)."""
    limit = min(int(request.args.get("limit", 5000)), 10_000)
    files = db.list_files(limit=limit)
    return jsonify(files)


@bp.route("/api/accounts/<int:aid>/role", methods=["PUT"])
@auth.login_required
def change_role(aid):
    """Switch an account's role between 'scan' and 'flix'."""
    data = request.get_json(force=True, silent=True) or {}
    new_role = (data.get("role") or "").strip()
    if new_role not in ("scan", "flix"):
        return jsonify({"ok": False, "error": "role must be 'scan' or 'flix'"}), 400
    try:
        db.change_account_role(aid, new_role)
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 409
    return jsonify({"ok": True, "role": new_role})


@bp.route("/api/accounts/<int:aid>/tokens", methods=["POST"])
@auth.login_required
def save_account_tokens(aid):
    """Save validation_key + jsessionid directly for a specific account by ID.

    Bypasses MSISDN matching — looks up by account ID from the URL.
    Body: { "validation_key": str, "jsessionid": str }
    """
    import time as _t
    data = request.get_json(force=True, silent=True) or {}
    vk  = (data.get("validation_key") or data.get("validationkey") or "").strip()
    jid = (data.get("jsessionid") or data.get("JSESSIONID") or "").strip()
    if not vk or not jid:
        return jsonify({"ok": False, "error": "validation_key and jsessionid are required"}), 400
    try:
        with db.conn() as c:
            row = c.execute("SELECT id, msisdn FROM accounts WHERE id=?", (aid,)).fetchone()
            if not row:
                return jsonify({"ok": False, "error": "Account not found"}), 404
            c.execute(
                "UPDATE accounts SET validation_key=?, jsessionid=?, "
                "token_expires_at=?, last_scan_at=? WHERE id=?",
                (vk, jid, int(_t.time() + 86400 * 30), int(_t.time()), aid)
            )
        msisdn = dict(row)["msisdn"]

        # Immediately verify the new JSESSIONID is alive + start keepalive coverage.
        # Without this, the 60-min idle timeout can kill the session before the
        # 15-min keepalive loop first touches this account.
        try:
            from .. import keepalive as _ka
            _ka.trigger_heartbeat(aid)
        except Exception as _hb_err:
            import logging
            logging.getLogger("hub.scan").debug("trigger_heartbeat failed: %s", _hb_err)

        # Clear all OTP backoffs so uploads/links resume immediately after re-activation.
        try:
            from .. import jazzdrive as _jd
            _jd.clear_sapi_backoff(aid)
        except Exception:
            pass
        try:
            from .. import uploader as _up
            _up.clear_refresh_backoff(aid)
        except Exception:
            pass

        return jsonify({
            "ok": True,
            "message": "Tokens saved — session verification triggered in background",
            "msisdn": msisdn,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/accounts/<int:aid>/sapi-activate-url", methods=["GET"])
@auth.login_required
def sapi_activate_url(aid):
    """Generate a JazzDrive SAPI activation URL from the stored raw_accesstoken.

    The returned URL can be opened in a phone browser on a Pakistani IP (Jazz network).
    The phone browser will display JSON containing validationkey and jsessionid which
    the user then pastes into the activation form — no PC/DevTools needed.
    """
    import json as _json
    import base64 as _b64
    import urllib.parse as _up

    CLOUD_BASE = "https://cloud.jazzdrive.com.pk"

    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT id, msisdn, raw_accesstoken FROM accounts WHERE id=?", (aid,)
            ).fetchone()
        if not row:
            return jsonify({"ok": False, "error": "Account not found"}), 404

        row = dict(row)
        raw_at = row.get("raw_accesstoken") or ""

        if not raw_at:
            return jsonify({
                "ok": False,
                "error": (
                    "No access token stored for account %s. "
                    "Please send an OTP first." % aid
                )
            }), 400

        at_json = _json.dumps({"data": {"accesstoken": raw_at}})
        at_b64e = _up.quote(_b64.b64encode(at_json.encode()).decode(), safe="")

        sapi_url = (
            f"{CLOUD_BASE}/sapi/login/oauth"
            f"?action=login&platform=Android&keytype=accesstoken&key={at_b64e}"
        )

        return jsonify({
            "ok": True,
            "sapi_url": sapi_url,
            "msisdn": row.get("msisdn", ""),
            "account_id": aid,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
@bp.route("/api/scan-all", methods=["POST"])
@auth.login_required
def scan_all():
    """Start a scan on every linked 'scan' account that isn't already running."""
    if db.setting("SCAN_ENABLED", "1") != "1":
        return jsonify({"ok": False, "error": "Scan is currently disabled — enable it in Settings → Services."}), 503
    accounts = db.list_accounts(role="scan")
    started, skipped, errors = [], [], []
    for a in accounts:
        aid = a["id"]
        if not a.get("token_expires_at"):
            skipped.append({"id": aid, "reason": "no session"})
            continue
        r = scan_mod.start_scan(aid)
        if r.get("ok"):
            started.append(aid)
        elif "already running" in (r.get("error") or "").lower():
            skipped.append({"id": aid, "reason": "already running"})
        else:
            errors.append({"id": aid, "error": r.get("error")})
    return jsonify({"ok": True, "started": started, "skipped": skipped, "errors": errors})


@bp.route("/api/duplicates")
@auth.login_required
def get_duplicates():
    """Return files with the same title indexed more than once."""
    limit = min(int(request.args.get("limit", 500)), 2000)
    rows = db.find_duplicates(limit=limit)
    return jsonify({"duplicates": rows, "count": len(rows)})


# ── Excluded folders ─────────────────────────────────────────────────────── #

import json as _json

def _load_excluded() -> list[str]:
    raw = db.setting("scan_excluded_folders") or "[]"
    try:
        return [x for x in _json.loads(raw) if x.strip()]
    except Exception:
        return []

def _save_excluded(lst: list[str]) -> None:
    db.set_setting("scan_excluded_folders", _json.dumps(list(dict.fromkeys(lst))))


@bp.route("/api/excluded-folders", methods=["GET"])
@auth.login_required
def get_excluded_folders():
    return jsonify({"folders": _load_excluded()})


@bp.route("/api/excluded-folders", methods=["POST"])
@auth.login_required
def add_excluded_folder():
    data = request.get_json(force=True, silent=True) or {}
    name = (data.get("name") or "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    lst = _load_excluded()
    if name not in lst:
        lst.append(name)
        _save_excluded(lst)
    return jsonify({"ok": True, "folders": lst})


@bp.route("/api/excluded-folders/<path:name>", methods=["DELETE"])
@auth.login_required
def del_excluded_folder(name):
    lst = [x for x in _load_excluded() if x != name]
    _save_excluded(lst)
    return jsonify({"ok": True, "folders": lst})


@bp.route('/api/accounts/<int:aid>/log', methods=['DELETE'])
@auth.login_required
def clear_log(aid):
    """Delete all scan log entries for this account from the DB."""
    import sqlite3 as _sq3
    db_path = '/opt/jazzmax/radd-hub/data/radd_hub.db'
    try:
        con = _sq3.connect(db_path, timeout=10)
        con.execute('PRAGMA journal_mode=WAL')
        con.execute('BEGIN IMMEDIATE')
        n = con.execute('DELETE FROM scan_log WHERE account_id=?', (aid,)).rowcount
        con.execute('COMMIT')
        con.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        con.close()
        return __import__('flask').jsonify({'ok': True, 'deleted': n})
    except Exception as e:
        return __import__('flask').jsonify({'ok': False, 'error': str(e)}), 500
