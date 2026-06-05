"""Flix — upload pipeline (watch-folder + manual) with dedicated JazzDrive account."""
import json as _json
import time as _time
from flask import Blueprint, render_template, request, jsonify, Response, stream_with_context
from .. import db, auth, uploader, config, scanner as scan_mod

bp = Blueprint("upload", __name__)


@bp.route("/")
@auth.login_required
def page():
    files = db.list_files(limit=30, source="upload")
    return render_template("upload.html",
        media_dir=str(config.MEDIA_DIR),
        stats=db.count_library(),
        recent=files)


# ---------------------------------------------------------------------------
# Trigger watch-folder scan
# ---------------------------------------------------------------------------

@bp.route("/api/scan-now", methods=["POST"])
@auth.login_required
def scan_now():
    n = uploader.trigger_scan_now()
    return jsonify({"ok": True, "queued": n})


# ---------------------------------------------------------------------------
# JazzDrive status & storage stats
# ---------------------------------------------------------------------------

@bp.route("/api/jd-stats")
@auth.login_required
def jd_stats():
    """Return JD session status, storage info, and library stats for the dashboard."""
    acct = uploader.get_active_account()
    lib  = db.count_library()

    if not acct:
        return jsonify({
            "ok": True,
            "session": {"logged_in": False, "msisdn": db.setting("JAZZDRIVE_MSISDN", "")},
            "storage": {"error": "no account"},
            "library_count": lib.get("files", 0),
            "library": lib,
        })

    vk   = acct.get("validation_key") or ""
    jsid = acct.get("jsessionid") or ""
    exp  = acct.get("token_expires_at") or 0
    has_rt  = bool((acct.get("refresh_token") or "").strip())
    has_at  = bool((acct.get("raw_accesstoken") or "").strip())
    token_ok = exp == 0 or exp > _time.time()

    # Cross-check with keepalive heartbeat results — DB expiry can lag reality
    # when refresh_token itself becomes invalid (e.g. invalid_grant from server).
    ka_cf = 0
    ka_last_error = ""
    try:
        from .. import keepalive as _ka
        ka_data = _ka.get_status()
        acct_ka = ka_data.get("accounts", {}).get(str(acct.get("id")), {})
        ka_cf = acct_ka.get("consecutive_failures", 0)
        ka_last_error = acct_ka.get("last_error") or ""
    except Exception:
        pass

    # Determine whether the session is truly dead based on keepalive data.
    # Two independent signals both trigger "dead":
    #   1. 3+ consecutive heartbeat failures (accumulated over time)
    #   2. The last error message explicitly says OTP/refresh is required
    #      (catches invalid_grant on the very first failure after restart)
    _err_lo = ka_last_error.lower()
    refresh_broken = (
        "invalid_grant" in _err_lo
        or "otp required" in _err_lo
        or "otp re-login" in _err_lo
        or "refresh failed" in _err_lo
    )
    keepalive_dead = ka_cf >= 3 or (ka_cf >= 1 and refresh_broken)
    if keepalive_dead:
        token_ok = False

    # logged_in: JSESSIONID present and token genuinely fresh (validation_key optional)
    logged_in = bool(jsid and token_ok)
    # needs_otp: session fully dead and no silent recovery path
    needs_otp = bool(
        jsid
        and not token_ok
        and (not has_rt and not has_at or refresh_broken)
    )

    storage = {}
    if token_ok and jsid:
        storage = uploader.get_storage_info(vk, jsid)

    remaining_m = max(0, int((exp - _time.time()) / 60)) if exp else 0

    return jsonify({
        "ok": True,
        "session": {
            "id":          acct.get("id"),
            "logged_in":   logged_in,
            "needs_otp":   needs_otp,
            "msisdn":      acct.get("msisdn") or db.setting("JAZZDRIVE_MSISDN", ""),
            "remaining_m": remaining_m,
            "has_refresh_token": has_rt,
        },
        "storage":       storage,
        "library_count": lib.get("files", 0),
        "library":       lib,
        "config": {
            "msisdn":       db.setting("JAZZDRIVE_MSISDN", ""),
            "share_email":  db.setting("JAZZDRIVE_SHARE_EMAIL", ""),
            "watch_root":   db.setting("upload_watch_root", str(config.MEDIA_DIR)),
            "max_parallel": int(db.setting("upload_parallel_uploads", "1") or 1),
            "max_size_gb":  float(db.setting("upload_max_file_size_gb", "0") or 0),
            "max_bps":      int(float(db.setting("upload_bandwidth_limit_mbps", "0") or 0) * 125000),
        },
    })


# ---------------------------------------------------------------------------
# Remote folder & media listing
# ---------------------------------------------------------------------------

@bp.route("/api/folders")
@auth.login_required
def api_folders():
    """List JazzDrive remote folders. ?parent=0"""
    parent_id = int(request.args.get("parent", 0))
    acct = uploader.get_active_account()
    if not acct:
        return jsonify({"ok": False, "error": "No active JazzDrive account"}), 400
    vk   = acct.get("validation_key") or ""
    jsid = acct.get("jsessionid") or ""
    if not vk or not jsid:
        return jsonify({"ok": False, "error": "No session tokens — login first"}), 400
    try:
        import requests as _req
        sess = _req.Session()
        folders = uploader._list_folders(sess, vk, jsid, parent_id)
        return jsonify({"ok": True, "folders": folders, "count": len(folders)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/media-items")
@auth.login_required
def api_media_items():
    """List JazzDrive remote media. ?type=video&parent=0"""
    media_type = (request.args.get("type") or "video").strip().lower()
    parent_id  = int(request.args.get("parent", 0))
    acct = uploader.get_active_account()
    if not acct:
        return jsonify({"ok": False, "error": "No active JazzDrive account"}), 400
    vk   = acct.get("validation_key") or ""
    jsid = acct.get("jsessionid") or ""
    if not vk or not jsid:
        return jsonify({"ok": False, "error": "No session tokens — login first"}), 400
    try:
        items = uploader.list_remote_media(vk, jsid, media_type, parent_id)
        return jsonify({"ok": True, "media": items, "count": len(items)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Manual file upload jobs
# ---------------------------------------------------------------------------

@bp.route("/api/manual-upload", methods=["POST"])
@auth.login_required
def manual_upload():
    """Queue a manual upload by absolute file path.
    Body: {path: str, parent_id: int}
    """
    data      = request.get_json(force=True, silent=True) or {}
    file_path = (data.get("path") or "").strip()
    parent_id = int(data.get("parent_id") or 0)
    if not file_path:
        return jsonify({"ok": False, "error": "path required"}), 400
    from pathlib import Path as _Path
    if not _Path(file_path).exists():
        return jsonify({"ok": False, "error": f"File not found: {file_path}"}), 400
    result = uploader.queue_manual_upload(file_path, parent_id=parent_id)
    return jsonify(result)


@bp.route("/api/jobs")
@auth.login_required
def api_jobs():
    """Return recent manual upload jobs + recent DB uploads merged and sorted."""
    manual = uploader.get_manual_jobs(limit=30)
    manual_set = {j["path"] for j in manual}

    db_uploads = db.list_files(limit=30, source="upload")
    db_jobs = []
    for f in db_uploads:
        path = f.get("local_path") or f.get("filename") or ""
        if path in manual_set:
            continue
        
        # Determine actual state from is_ready
        # 1 = done, 0 = queued, -2 = uploading, -1 = skipped/failed
        is_ready = f.get("is_ready", 1)
        state = "done"
        if is_ready == 0: state = "queued"
        elif is_ready == -2: state = "uploading"
        elif is_ready == -1: state = "failed"

        db_jobs.append({
            "id":         f"db:{f['id']}",
            "path":       path,
            "state":      state,
            "uploaded":   f.get("size_bytes") or 0 if state == "done" else 0,
            "total":      f.get("size_bytes") or 0,
            "percent":    100 if state == "done" else 0,
            "error":      None,
            "started_at": f.get("uploaded_at") or 0,
            "share_url":  f.get("share_url"),
        })

    all_jobs = manual + db_jobs
    all_jobs.sort(key=lambda j: j.get("started_at", 0), reverse=True)
    return jsonify({"ok": True, "jobs": all_jobs[:50]})


# ---------------------------------------------------------------------------
# Library browse & delete (Flix uploads only)
# ---------------------------------------------------------------------------

@bp.route("/api/library")
@auth.login_required
def api_library():
    """List uploaded library entries. ?q=title&limit=200"""
    q     = (request.args.get("q") or "").strip()
    limit = min(int(request.args.get("limit", 200)), 500)
    with db.conn() as c:
        sql = ("SELECT f.id, f.fingerprint, f.filename, f.size_bytes, f.share_url, "
               "       f.uploaded_at, f.account_id, "
               "       t.title, t.year, t.media_type, t.poster "
               "FROM files f LEFT JOIN titles t ON t.id = f.title_id "
               "WHERE f.source IN ('upload','download') ")
        args: list = []
        if q:
            sql += "AND (f.filename LIKE ? OR t.title LIKE ?) "
            args += [f"%{q}%", f"%{q}%"]
        sql += "ORDER BY f.uploaded_at DESC LIMIT ?"
        args.append(limit)
        rows = [dict(r) for r in c.execute(sql, args).fetchall()]
    items = []
    for r in rows:
        items.append({
            "id":          r["id"],
            "fingerprint": r["fingerprint"],
            "name":        r["filename"],
            "title":       r["title"] or r["filename"],
            "year":        r["year"] or "",
            "kind":        r["media_type"] or "movie",
            "size_bytes":  r["size_bytes"] or 0,
            "share_url":   r["share_url"] or "",
            "uploaded_at": r["uploaded_at"],
            "poster":      r["poster"] or "",
        })
    return jsonify({"ok": True, "items": items, "count": len(items)})


@bp.route("/api/library/<path:fp>", methods=["DELETE"])
@auth.login_required
def api_library_delete(fp: str):
    """Delete a library entry by fingerprint."""
    with db.conn() as c:
        c.execute("DELETE FROM files WHERE fingerprint=?", (fp,))
    return jsonify({"ok": True})


# ---------------------------------------------------------------------------
# Upload configuration
# ---------------------------------------------------------------------------

@bp.route("/api/config", methods=["GET"])
@auth.login_required
def api_config_get():
    """Return current upload configuration."""
    return jsonify({
        "ok": True,
        "config": {
            "msisdn":       db.setting("JAZZDRIVE_MSISDN", ""),
            "share_email":  db.setting("JAZZDRIVE_SHARE_EMAIL", ""),
            "watch_root":   db.setting("upload_watch_root", str(config.MEDIA_DIR)),
            "max_parallel": int(db.setting("upload_parallel_uploads", "1") or 1),
            "max_size_gb":  float(db.setting("upload_max_file_size_gb", "0") or 0),
            "max_bps":      int(float(db.setting("upload_bandwidth_limit_mbps", "0") or 0) * 125000),
        },
    })


@bp.route("/api/config", methods=["POST"])
@auth.login_required
def api_config_post():
    """Save upload configuration settings."""
    data = request.get_json(force=True, silent=True) or {}
    updated = []

    def _set(key, val):
        if val is not None:
            db.set_setting(key, str(val))
            updated.append(key)

    if "msisdn" in data:
        _set("JAZZDRIVE_MSISDN", data["msisdn"])
    if "share_email" in data:
        _set("JAZZDRIVE_SHARE_EMAIL", data["share_email"])
    if "watch_root" in data:
        _set("upload_watch_root", data["watch_root"])
    if "max_parallel" in data:
        _set("upload_parallel_uploads", int(data["max_parallel"] or 1))
    if "max_size_gb" in data:
        _set("upload_max_file_size_gb", float(data["max_size_gb"] or 0))
    if "max_bps" in data:
        bps = int(data["max_bps"] or 0)
        mbps = bps / 125000.0
        _set("upload_bandwidth_limit_mbps", round(mbps, 3))

    return jsonify({"ok": True, "updated": updated})


# ---------------------------------------------------------------------------
# Simplified OTP login (msisdn-first — auto-creates account if needed)
# ---------------------------------------------------------------------------

@bp.route("/api/login/otp", methods=["POST"])
@auth.login_required
def login_send_otp():
    """Send OTP to a Jazz mobile number. Auto-creates account if missing.
    Body: {msisdn: str}
    """
    data   = request.get_json(force=True, silent=True) or {}
    msisdn = db.normalize_msisdn(data.get("msisdn"))
    if not msisdn:
        return jsonify({"ok": False, "error": "msisdn required"}), 400
    try:
        aid = db.upsert_account(msisdn=msisdn, label=f"JazzDrive {msisdn}", role="flix")
    except ValueError as e:
        return jsonify({"ok": False, "error": str(e)}), 409
    return jsonify(scan_mod.send_otp(aid))


@bp.route("/api/login/resend", methods=["POST"])
@auth.login_required
def login_resend_otp():
    """Resend OTP for a number that was sent via /api/login/otp.
    Body: {msisdn: str}
    """
    data   = request.get_json(force=True, silent=True) or {}
    msisdn = db.normalize_msisdn(data.get("msisdn"))
    if not msisdn:
        return jsonify({"ok": False, "error": "msisdn required"}), 400
    
    with db.conn() as c:
        row = c.execute("SELECT id FROM accounts WHERE msisdn=? AND role='flix' LIMIT 1",
                        (msisdn,)).fetchone()
    
    if not row:
        return jsonify({"ok": False, "error": f"Account {msisdn} not found"}), 404
    
    return jsonify(scan_mod.resend_otp(row["id"]))


@bp.route("/api/login/verify", methods=["POST"])
@auth.login_required
def login_verify_otp():
    """Verify OTP for a number that was sent via /api/login/otp.
    Body: {msisdn: str, otp: str}
    """
    data   = request.get_json(force=True, silent=True) or {}
    msisdn = db.normalize_msisdn(data.get("msisdn"))
    otp    = (data.get("otp") or "").strip()
    if not msisdn or not otp:
        return jsonify({"ok": False, "error": "msisdn and otp required"}), 400
    
    with db.conn() as c:
        row = c.execute("SELECT id FROM accounts WHERE msisdn=? AND role='flix' LIMIT 1",
                        (msisdn,)).fetchone()
    
    if not row:
        return jsonify({"ok": False, "error": f"Account {msisdn} not found — did you send OTP first?"}), 404
    
    try:
        return jsonify(scan_mod.verify_otp(row["id"], otp))
    except Exception as e:
        return jsonify({"ok": False, "error": f"Verification system error: {e}"}), 500


@bp.route("/api/sapi-activate-url", methods=["POST"])
@auth.login_required
def upload_sapi_activate_url():
    """Generate a JazzDrive SAPI phone-activation URL for the flix account.
    Body: {msisdn: str}  OR  {account_id: int}
    Returns the same URL as the scan page's sapi-activate-url — independent system.
    """
    import json as _json, base64 as _b64, urllib.parse as _up
    CLOUD_BASE = "https://cloud.jazzdrive.com.pk"
    data = request.get_json(force=True, silent=True) or {}
    msisdn = db.normalize_msisdn(data.get("msisdn") or "")
    aid    = data.get("account_id")
    try:
        with db.conn() as c:
            if aid:
                row = c.execute("SELECT id, msisdn, raw_accesstoken FROM accounts WHERE id=?", (aid,)).fetchone()
            elif msisdn:
                row = c.execute("SELECT id, msisdn, raw_accesstoken FROM accounts WHERE msisdn=? LIMIT 1", (msisdn,)).fetchone()
            else:
                return jsonify({"ok": False, "error": "msisdn or account_id required"}), 400
        if not row:
            return jsonify({"ok": False, "error": "Account not found"}), 404
        row = dict(row)
        raw_at = row.get("raw_accesstoken") or ""
        if not raw_at:
            return jsonify({"ok": False, "error": "No access token stored — send OTP first"}), 400
        at_json  = _json.dumps({"data": {"accesstoken": raw_at}})
        at_b64e  = _up.quote(_b64.b64encode(at_json.encode()).decode(), safe="")
        sapi_url = (f"{CLOUD_BASE}/sapi/login/oauth"
                    f"?action=login&platform=Android&keytype=accesstoken&key={at_b64e}")
        return jsonify({"ok": True, "sapi_url": sapi_url,
                        "msisdn": row.get("msisdn", ""), "account_id": row["id"]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/upload-file", methods=["POST"])
@auth.login_required
def api_upload_file():
    """Accept a file upload from the browser (multipart/form-data).

    The file is saved into MEDIA_DIR so the watcher loop picks it up and
    uploads it to JazzDrive automatically.  Works for paste-from-clipboard,
    drag-and-drop, and the file-chooser dialog.
    """
    import os as _os
    from pathlib import Path as _Path
    from werkzeug.utils import secure_filename as _sec

    if "file" not in request.files:
        return jsonify({"ok": False, "error": "No file field in request"}), 400
    f = request.files["file"]
    if not f or not f.filename:
        return jsonify({"ok": False, "error": "Empty filename"}), 400

    safe_name = _sec(f.filename)
    dest = config.MEDIA_DIR / safe_name
    config.MEDIA_DIR.mkdir(parents=True, exist_ok=True)
    f.save(str(dest))

    # Trigger an immediate watcher scan so it shows up in jobs without
    # waiting up to 30 s for the next automatic tick.
    try:
        n = uploader.trigger_scan_now()
    except Exception:
        n = 0

    return jsonify({"ok": True, "filename": safe_name,
                    "path": str(dest), "queued": n})


@bp.route("/api/account", methods=["DELETE"])
@auth.login_required
def api_delete_account():
    """Delete the current flix account entirely (so a new one can be registered)."""
    with db.conn() as c:
        row = c.execute("SELECT id FROM accounts WHERE role='flix' LIMIT 1").fetchone()
    if not row:
        return jsonify({"ok": True, "message": "No flix account to delete"})
    db.delete_account(row["id"])
    return jsonify({"ok": True, "message": "Flix account deleted"})


@bp.route("/api/all-accounts")
@auth.login_required
def api_all_accounts():
    """Return every account (including inactive) so the UI can show stale ones."""
    with db.conn() as c:
        rows = c.execute("SELECT id, msisdn, label, role, is_active, "
                         "validation_key, jsessionid, created_at FROM accounts ORDER BY id").fetchall()
    return jsonify({"ok": True, "accounts": [dict(r) for r in rows]})


@bp.route("/api/logout", methods=["POST"])
@auth.login_required
def api_logout():
    """Clear JazzDrive session tokens from the active account."""
    acct = uploader.get_active_account()
    if not acct:
        return jsonify({"ok": True, "message": "No active account"})
    try:
        with db.conn() as c:
            c.execute("UPDATE accounts SET validation_key='', jsessionid='', "
                      "token_expires_at=0 WHERE id=?", (acct["id"],))
        return jsonify({"ok": True, "message": "Logged out"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/jazzdrive/tokens", methods=["POST"])
@auth.login_required
def api_paste_tokens():
    """Directly save validation_key + JSESSIONID cookies pasted from browser.

    Used when the server IP is blocked by JazzDrive for silent session init —
    the user logs in at cloud.jazzdrive.com.pk in their browser, copies the
    two session cookies from DevTools, and pastes them here.

    Body: {validation_key: str, jsessionid: str, msisdn?: str}
    """
    import time as _time
    data = request.get_json(force=True, silent=True) or {}
    vk  = (data.get("validation_key") or "").strip()
    jid = (data.get("jsessionid") or "").strip()
    msisdn_raw = data.get("msisdn") or ""

    if not vk or not jid:
        return jsonify({"ok": False, "error": "validation_key and jsessionid are required"}), 400

    # Find the active flix account; fall back to the provided msisdn
    acct = uploader.get_active_account()
    if not acct and msisdn_raw:
        msisdn = db.normalize_msisdn(msisdn_raw)
        with db.conn() as c:
            row = c.execute(
                "SELECT id FROM accounts WHERE msisdn=? LIMIT 1", (msisdn,)
            ).fetchone()
        acct = dict(row) if row else None

    if not acct:
        return jsonify({"ok": False, "error": "No JazzDrive account found — send OTP first"}), 404

    aid = acct["id"]
    exp = int(_time.time()) + 86400 * 30  # treat as valid for 30 days

    try:
        with db.conn() as c:
            c.execute(
                "UPDATE accounts SET validation_key=?, jsessionid=?, "
                "token_expires_at=?, is_active=1 WHERE id=?",
                (vk, jid, exp, aid),
            )
        return jsonify({"ok": True, "message": "Tokens saved — session active", "account_id": aid})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Live log stream (SSE)
# ---------------------------------------------------------------------------

@bp.route("/api/log-stream")
@auth.login_required
def api_log_stream():
    """Server-Sent Events stream of upload/keepalive log entries.

    Query param: ?since=<seq>  (0 = send last 100 stored entries first)
    The client reconnects automatically on drop; the seq cursor prevents
    duplicate entries.
    """
    since = int(request.args.get("since", 0))

    @stream_with_context
    def _generate():
        cursor = since
        # Send buffered history on first connect
        entries = uploader.get_log_entries(since_seq=max(0, cursor))
        for e in entries:
            yield f"data: {_json.dumps(e)}\n\n"
            cursor = max(cursor, e["seq"])

        # Poll for new entries every second
        idle = 0
        while True:
            _time.sleep(1)
            new = uploader.get_log_entries(since_seq=cursor)
            if new:
                idle = 0
                for e in new:
                    yield f"data: {_json.dumps(e)}\n\n"
                    cursor = max(cursor, e["seq"])
            else:
                idle += 1
                # Send keepalive comment every 15 s so proxy doesn't close connection
                if idle % 15 == 0:
                    yield ": keepalive\n\n"

    return Response(
        _generate(),
        mimetype="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@bp.route("/api/log-entries")
@auth.login_required
def api_log_entries():
    """Return log entries as JSON. ?since=<seq>"""
    since = int(request.args.get("since", 0))
    entries = uploader.get_log_entries(since_seq=since)
    return jsonify({"ok": True, "entries": entries,
                    "count": len(entries)})


# ---------------------------------------------------------------------------
# Heartbeat history
# ---------------------------------------------------------------------------

@bp.route("/api/heartbeat-history")
@auth.login_required
def api_heartbeat_history():
    """Return keepalive heartbeat history from the keepalive worker."""
    try:
        from .. import keepalive as _ka
        status = _ka.get_status()
        accounts_status = status.get("accounts", {})

        # Determine if the worker is running (it's a daemon thread — if the
        # dict exists it's been started)
        import threading as _th
        worker_alive = any(
            t.name == "keepalive" or "keepalive" in t.name.lower()
            for t in _th.enumerate()
        )

        # Pull scan_log events for historical heartbeat records if table exists
        history = []
        try:
            with db.conn() as c:
                rows = c.execute(
                    "SELECT * FROM scan_log "
                    "WHERE kind IN ('keepalive_ok','keepalive_fail') "
                    "ORDER BY ts DESC LIMIT 200"
                ).fetchall()
                history = [dict(r) for r in rows]
        except Exception:
            pass

        return jsonify({
            "ok": True,
            "worker": {
                "running": worker_alive,
                "started_at": status.get("worker_started_at"),
                "interval_min": 15,
            },
            "accounts": accounts_status,
            "history": history,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Reset stuck files
# ---------------------------------------------------------------------------

@bp.route("/api/reset-stuck", methods=["POST"])
@auth.login_required
def api_reset_stuck():
    """Reset files stuck at is_ready=-2 or -1 back to pending (0)."""
    data = request.get_json(force=True, silent=True) or {}
    include_skipped = data.get("include_skipped", False)
    try:
        with db.conn() as c:
            n2 = c.execute(
                "UPDATE files SET is_ready=0 WHERE is_ready=-2"
            ).rowcount
            n1 = 0
            if include_skipped:
                n1 = c.execute(
                    "UPDATE files SET is_ready=0 WHERE is_ready=-1"
                ).rowcount
        return jsonify({"ok": True, "reset_inprogress": n2, "reset_skipped": n1})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
