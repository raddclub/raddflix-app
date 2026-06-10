"""THE one settings page - multi-key vault for everything."""
import json
from flask import Blueprint, render_template, request, jsonify
from .. import db, keys, auth, config

bp = Blueprint("settings", __name__)


GROUPS = [
    {"id": "tmdb",    "title": "TMDB (movie metadata)",       "providers": ["tmdb"],
     "doc": "Get a free key at https://www.themoviedb.org/settings/api"},
    {"id": "ai",      "title": "AI providers",                "providers": ["groq", "gemini", "openai", "openrouter"],
     "doc": "Used to classify movies and pick the best site."},
    {"id": "github",  "title": "GitHub mirror",               "providers": ["github"],
     "doc": "Personal access token with 'repo' scope. Add as many as you like - they auto-rotate."},
    {"id": "gsheets", "title": "Google Sheets mirror",        "providers": ["gsheets_sa_json"],
     "doc": "Paste the full service-account JSON. Multiple supported - auto-rotation."},
    {"id": "telegram","title": "Telegram bot",                "providers": ["telegram"]},
    {"id": "omdb",    "title": "OMDB (alt metadata)",         "providers": ["omdb"]},
    {"id": "fcm",     "title": "FCM Push Notifications",         "providers": ["fcm"],
     "doc": "Firebase Cloud Messaging server key. Get from Firebase Console → Project Settings → Cloud Messaging → Server key. Required for push notifications (TID approved/rejected alerts)."},
]

NON_VAULT_SETTINGS = [
    ("github_repo",    "GitHub repo (owner/name)", "text"),
    ("github_branch",  "GitHub branch",            "text"),
    ("github_db_path", "Path inside repo",         "text"),
    ("gsheet_id",      "Google Sheet ID",          "text"),
    ("gsheet_name",    "Worksheet name",           "text"),
]

UPLOAD_CFG_SETTINGS = [
    ("upload_parallel_uploads",     "Parallel uploads",          "number",
     "How many files to upload simultaneously (default 1)"),
    ("upload_max_file_size_gb",     "Max file size (GB)",        "number",
     "Skip files larger than this. 0 = no limit (default 4)"),
    ("upload_bandwidth_limit_mbps", "Bandwidth limit (Mbps)",    "number",
     "Throttle upload speed. 0 = unlimited (default 0)"),
    ("upload_chunk_size_mb",        "Chunk size (MB)",           "number",
     "Streaming chunk size for uploads (default 4)"),
    ("upload_max_retries",          "Max retries on failure",    "number",
     "Retry count per file on transient errors (default 3)"),
    ("upload_retry_base_delay",     "Retry base delay (s)",      "number",
     "Seconds to wait before first retry (default 2)"),
    ("upload_skip_extensions",      "Skip extensions",           "text",
     "Comma-separated extensions to skip e.g. .sample,.nfo (default empty)"),
]

UPLOAD_TOGGLE_SETTINGS = [
    ("upload_auto_delete", "Auto-delete local file after upload",
     "Delete the local copy once the file is successfully uploaded and a share link is created. "
     "Disable to keep local copies. (default: on)"),
]



# JazzDrive / bot env settings stored in the settings k/v table
# (not the key vault — these are plain config, not secrets)
JD_BOT_SETTINGS = [
    ("JAZZDRIVE_MSISDN",              "jazzdrive", "JazzDrive MSISDN",                  "Primary phone number (923xxxxxxxxx)"),
    ("JAZZDRIVE_SHARE_EMAIL",         "jazzdrive", "JazzDrive share email",              "Email used when creating share links"),
    ("JAZZDRIVE_KEEPALIVE_INTERVAL",  "jazzdrive", "Keepalive interval (seconds)",       "Default: 2700 (45 min)"),
    ("SUPPORT_WHATSAPP_NUMBER",        "whatsapp",  "Support WhatsApp number",            "International format, no + or spaces e.g. 923257719165"),
    ("BOT_ADMIN_JIDS",                "whatsapp",  "WhatsApp admin JIDs",               "Comma-separated JIDs: 923…@s.whatsapp.net"),
    ("BOT_RATE_LIMIT_PER_MIN",        "whatsapp",  "Rate limit per minute",             "Requests per minute per user (default 12)"),
    ("BOT_RATE_LIMIT_ADMIN_BYPASS",   "whatsapp",  "Admin rate-limit bypass",           "1 = admins skip rate limits"),
    ("TELEGRAM_ADMIN_IDS",            "telegram",  "Telegram admin IDs",               "Comma-separated chat IDs"),
    ("TG_RATE_LIMIT_PER_MIN",         "telegram",  "Telegram rate limit / min",        "Default 12"),
]


@bp.route("/")
@auth.login_required
def page():
    items = []
    for g in GROUPS:
        provs = []
        for p in g["providers"]:
            provs.append({"provider": p, "keylist": keys.list_keys(p)})
        items.append({"group": g, "providers": provs})
    settings_kv = {k: db.setting(k, "") or "" for k, _, _ in NON_VAULT_SETTINGS}
    # Build grouped env settings for display
    from itertools import groupby
    jd_bot_grouped = {}
    for env_key, group_id, label, hint in JD_BOT_SETTINGS:
        jd_bot_grouped.setdefault(group_id, []).append({
            "key": env_key, "label": label, "hint": hint,
            "value": db.setting(env_key, "") or "",
        })
    upload_cfg = [
        {"key": k, "label": lbl, "type": t, "hint": hint,
         "value": db.setting(k, "") or ""}
        for k, lbl, t, hint in UPLOAD_CFG_SETTINGS
    ]
    upload_toggles = [
        {"key": k, "label": lbl, "hint": hint,
         "value": db.setting(k, "1") not in ("0", "false", "no", "")}
        for k, lbl, hint in UPLOAD_TOGGLE_SETTINGS
    ]
    return render_template("settings.html",
        groups=items,
        settings=settings_kv,
        non_vault=NON_VAULT_SETTINGS,
        media_dir=str(config.MEDIA_DIR),
        staging_dir=str(config.STAGING_DIR),
        jd_bot_grouped=jd_bot_grouped,
        upload_cfg=upload_cfg,
        upload_toggles=upload_toggles,
    )


# ---------- key vault API ------------------------------------------------- #

@bp.route("/api/keys", methods=["GET"])
@auth.login_required
def api_list():
    prov = request.args.get("provider")
    return jsonify(keys.list_keys(prov))


@bp.route("/api/keys", methods=["POST"])
@auth.login_required
def api_add():
    data = request.get_json(force=True, silent=True) or request.form
    p = (data.get("provider") or "").strip()
    v = (data.get("value") or "").strip()
    label = (data.get("label") or "").strip()
    if not p or not v:
        return jsonify({"error": "provider and value required"}), 400
    try:
        kid = keys.add_key(p, v, label)
        return jsonify({"ok": True, "id": kid})
    except Exception as e:
        return jsonify({"error": str(e)}), 400


@bp.route("/api/keys/<int:kid>", methods=["DELETE"])
@auth.login_required
def api_del(kid):
    keys.remove_key(kid)
    return jsonify({"ok": True})


@bp.route("/api/keys/<int:kid>/toggle", methods=["POST"])
@auth.login_required
def api_toggle(kid):
    data = request.get_json(force=True, silent=True) or {}
    keys.set_active(kid, bool(data.get("active", True)))
    return jsonify({"ok": True})


@bp.route("/api/keys/<int:kid>/test", methods=["POST"])
@auth.login_required
def api_test(kid):
    rows = [k for k in keys.list_keys(mask=False) if k["id"] == kid]
    if not rows:
        return jsonify({"ok": False, "message": "not found"}), 404
    k = rows[0]
    res = keys.test_provider(k["provider"], k["value"])
    if res.get("ok"):
        keys.mark_ok(k["provider"], k["value"])
    return jsonify(res)




# ---------- setup status (used by Getting Started card) -------------------- #

@bp.route("/api/setup-status")
@auth.login_required
def api_setup_status():
    """Return key counts + title enrichment stats for the Getting Started card."""
    providers = ["tmdb", "omdb", "groq", "gemini", "openai", "openrouter"]
    key_counts = {}
    for p in providers:
        active = [k for k in keys.list_keys(p) if k.get("is_active")]
        key_counts[p] = len(active)

    stats = {"total": 0, "poster": 0, "rating": 0, "overview": 0, "genres": 0}
    try:
        with db.conn() as c:
            stats["total"]    = c.execute("SELECT COUNT(*) FROM titles").fetchone()[0]
            stats["poster"]   = c.execute("SELECT COUNT(*) FROM titles WHERE poster_url IS NOT NULL AND CAST(poster_url AS TEXT) != ''").fetchone()[0]
            stats["rating"]   = c.execute("SELECT COUNT(*) FROM titles WHERE imdb_rating IS NOT NULL").fetchone()[0]
            stats["overview"] = c.execute("SELECT COUNT(*) FROM titles WHERE overview IS NOT NULL AND CAST(overview AS TEXT) != ''").fetchone()[0]
            stats["genres"]   = c.execute("SELECT COUNT(*) FROM titles WHERE genres_csv IS NOT NULL AND CAST(genres_csv AS TEXT) != ''").fetchone()[0]
    except Exception:
        pass

    has_tmdb = key_counts.get("tmdb", 0) > 0
    has_omdb = key_counts.get("omdb", 0) > 0
    has_ai   = any(key_counts.get(p, 0) > 0 for p in ["groq", "gemini", "openai", "openrouter"])

    return jsonify({
        "keys": key_counts,
        "has_tmdb": has_tmdb,
        "has_omdb": has_omdb,
        "has_ai": has_ai,
        "titles": stats,
        "ready": has_tmdb or has_omdb or has_ai,
    })

# ---------- non-vault settings (repo names, sheet IDs) -------------------- #

@bp.route("/api/settings", methods=["POST"])
@auth.login_required
def api_settings_save():
    data = request.get_json(force=True, silent=True) or request.form
    # mirror destination settings
    for k, _, _ in NON_VAULT_SETTINGS:
        if k in data:
            db.set_setting(k, str(data.get(k) or ""))
    

# JazzDrive / bot env settings
    for env_key, _, _, _ in JD_BOT_SETTINGS:
        if env_key in data:
            db.set_setting(env_key, str(data.get(env_key) or ""))
    # Upload config settings
    for k, _, _, _ in UPLOAD_CFG_SETTINGS:
        if k in data:
            db.set_setting(k, str(data.get(k) or ""))
    # Upload toggle settings (booleans sent as "1"/"0" from checkbox)
    for k, _, _ in UPLOAD_TOGGLE_SETTINGS:
        if k in data:
            v = data.get(k)
            db.set_setting(k, "1" if str(v).lower() in ("1", "true", "yes", "on") else "0")
    return jsonify({"ok": True})


@bp.route("/api/proxies", methods=["GET"])
@auth.login_required
def api_proxies_get():
    """Return the list of proxies and current selection status."""
    proxies_json = db.setting("JAZZDRIVE_PROXIES")
    proxies = []
    if proxies_json:
        try:
            proxies = json.loads(proxies_json)
        except Exception:
            proxies = []

    # Auto-seed from SAPI pool when list is empty (first open or cleared).
    # This means the OTP proxy modal is never empty on a configured server.
    if not proxies:
        try:
            from .. import proxy_pool as _pp
            chain = _pp.pool.get_proxy_chain(n=8)
            proxies = [
                {"url": (px.get("_url") or px.get("https") or px.get("http", "")), "status": "working"}
                for px in chain
                if (px.get("_url") or px.get("https") or px.get("http", ""))
            ]
        except Exception:
            pass
        if not proxies:
            # Hard fallback if pool is also empty
            proxies = [
                {"url": "socks5://103.121.120.242:1080", "status": "untested"},
                {"url": "socks5://103.236.134.210:1080", "status": "untested"},
                {"url": "http://103.141.144.116:8080",   "status": "untested"},
                {"url": "http://202.141.240.26:8080",    "status": "untested"},
                {"url": "http://111.119.160.18:8080",    "status": "untested"},
            ]
        db.set_setting("JAZZDRIVE_PROXIES", json.dumps(proxies))

    return jsonify({
        "proxies": proxies,
        "enabled": db.setting("JAZZDRIVE_PROXY_ENABLED", "0") == "1",
        "active_url": db.setting("JAZZDRIVE_PROXY", "")
    })


@bp.route("/api/proxies", methods=["POST"])
@auth.login_required
def api_proxies_save():
    """Save the full list of proxies."""
    data = request.get_json(force=True, silent=True) or {}
    proxies = data.get("proxies")
    if not isinstance(proxies, list):
        return jsonify({"error": "proxies must be a list"}), 400
    
    db.set_setting("JAZZDRIVE_PROXIES", json.dumps(proxies))
    return jsonify({"ok": True})


@bp.route("/api/proxies/toggle", methods=["POST"])
@auth.login_required
def api_proxies_toggle():
    """Toggle whether proxy usage is enabled globally."""
    data = request.get_json(force=True, silent=True) or {}
    enabled = data.get("enabled", False)
    db.set_setting("JAZZDRIVE_PROXY_ENABLED", "1" if enabled else "0")
    return jsonify({"ok": True, "enabled": enabled})




@bp.route("/api/proxies/bypass", methods=["GET", "POST"])
@auth.login_required
def api_proxies_bypass():
    """GET: bypass state. POST {bypass:bool}: set JAZZDRIVE_PROXY_BYPASS."""
    if request.method == "GET":
        return jsonify({"ok": True, "bypass": db.setting("JAZZDRIVE_PROXY_BYPASS", "0") == "1"})
    data = request.get_json(force=True, silent=True) or {}
    bypass = bool(data.get("bypass", False))
    db.set_setting("JAZZDRIVE_PROXY_BYPASS", "1" if bypass else "0")
    import logging; logging.getLogger("hub.jazzdrive").info("PROXY_BYPASS -> %s via UI", "DIRECT" if bypass else "PROXY")
    return jsonify({"ok": True, "bypass": bypass})

@bp.route("/api/proxies/select", methods=["POST"])
@auth.login_required
def api_proxies_select():
    """Select which proxy to use from the list."""
    data = request.get_json(force=True, silent=True) or {}
    url = data.get("url", "").strip()
    db.set_setting("JAZZDRIVE_PROXY", url)
    return jsonify({"ok": True, "active_url": url})


@bp.route("/api/proxy-test", methods=["POST"])
@auth.login_required
def api_proxy_test():
    """Test if a proxy can reach JazzDrive OTP/Auth endpoints.

    BLOCKED on Replit — proxy traffic violates ToS and gets the Repl banned."""
    import requests, os
    if os.environ.get("REPL_ID") or os.environ.get("REPLIT_DEPLOYMENT"):
        return jsonify({
            "ok": False,
            "message": "Proxy testing is disabled on Replit (violates ToS). Use your own server or deploy outside Replit to enable proxies."
        }), 403

    import time
    data = request.get_json(force=True, silent=True) or {}
    url = data.get("url", "").strip()
    if not url:
        url = db.setting("JAZZDRIVE_PROXY", "")

    if not url:
        return jsonify({"ok": False, "message": "No proxy URL provided"}), 400

    proxies = {"http": url, "https": url}
    start = time.time()
    try:
        # Test against the bare domain which has the SSL mismatch
        # This is where OTP/Token requests go.
        r = requests.get("https://jazzdrive.com.pk/oauth2/refresh_token.php", 
                         proxies=proxies, timeout=15, verify=False)
        elapsed = time.time() - start
        
        # Also try to get the external IP to verify it's really working
        ip = "unknown"
        try:
            ip_r = requests.get("https://api.ipify.org?format=json", 
                                proxies=proxies, timeout=5)
            ip = ip_r.json().get("ip", "unknown")
        except: pass
            
        return jsonify({
            "ok": True,
            "message": f"Reached JazzDrive in {elapsed:.2f}s (IP: {ip})",
            "ping": int(elapsed * 1000)
        })
    except Exception as e:
        return jsonify({"ok": False, "message": str(e)})


# ── App Version Control API ────────────────────────────────────────────────────

APP_VERSION_KEYS = [
    "app_min_version_code",
    "app_current_version",
    "app_update_url",
    "app_check_signature",
    "app_force_update_at",
    "app_block_on_tamper",
    "app_crack_message",
]

@bp.route("/api/app-version")
@auth.login_required
def get_app_version():
    result = {}
    for k in APP_VERSION_KEYS:
        result[k] = db.setting(k, "") or ""
    # Also return signatures list
    try:
        with db.conn() as c:
            sigs = c.execute(
                "SELECT id, sig_hash, label, is_allowed, note, created_at FROM app_signatures ORDER BY created_at DESC"
            ).fetchall()
        result["signatures"] = [dict(s) for s in sigs]
    except Exception:
        result["signatures"] = []
    return jsonify(result)


@bp.route("/api/app-version", methods=["POST"])
@auth.login_required
def save_app_version():
    data = request.get_json(force=True, silent=True) or request.form.to_dict()
    saved = []
    for k in APP_VERSION_KEYS:
        if k in data:
            v = str(data[k]).strip()
            db.set_setting(k, v)
            saved.append(k)
    return jsonify({"ok": True, "saved": saved})


@bp.route("/api/app-signatures", methods=["POST"])
@auth.login_required
def add_signature():
    data = request.get_json(force=True, silent=True) or {}
    sig_hash  = str(data.get("sig_hash",  "")).strip().upper().replace(":", "").replace(" ", "")
    label     = str(data.get("label",     "")).strip()[:80]
    is_allowed = int(data.get("is_allowed", 1))
    note      = str(data.get("note",      "")).strip()[:200]
    if len(sig_hash) < 8:
        return jsonify({"error": "sig_hash required (min 8 chars)"}), 400
    try:
        with db.conn() as c:
            c.execute(
                "INSERT OR REPLACE INTO app_signatures(sig_hash,label,is_allowed,note) VALUES(?,?,?,?)",
                (sig_hash, label, is_allowed, note)
            )
            row_id = c.execute("SELECT last_insert_rowid() AS id").fetchone()["id"]
        return jsonify({"ok": True, "id": row_id})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@bp.route("/api/services", methods=["GET", "POST"])
@auth.login_required
def api_services():
    """GET: return current SCAN_ENABLED / UPLOAD_ENABLED / ORGANIZER_ENABLED flags.
    POST {scan?: bool, upload?: bool, organizer?: bool}: toggle services."""
    if request.method == "GET":
        return jsonify({
            "ok": True,
            "scan_enabled":      db.setting("SCAN_ENABLED",      "1") == "1",
            "upload_enabled":    db.setting("UPLOAD_ENABLED",    "1") == "1",
            "organizer_enabled": db.setting("ORGANIZER_ENABLED", "1") == "1",
        })
    data = request.get_json(force=True, silent=True) or {}
    if "scan" in data:
        db.set_setting("SCAN_ENABLED",      "1" if data["scan"]      else "0")
    if "upload" in data:
        db.set_setting("UPLOAD_ENABLED",    "1" if data["upload"]    else "0")
    if "organizer" in data:
        db.set_setting("ORGANIZER_ENABLED", "1" if data["organizer"] else "0")
    return jsonify({
        "ok": True,
        "scan_enabled":      db.setting("SCAN_ENABLED",      "1") == "1",
        "upload_enabled":    db.setting("UPLOAD_ENABLED",    "1") == "1",
        "organizer_enabled": db.setting("ORGANIZER_ENABLED", "1") == "1",
    })


@bp.route("/api/services/status")
@auth.login_required
def api_services_status():
    """Live worker health for all three services: upload, scan, organizer."""
    import threading as _th, time as _time
    from .. import self_heal as _sh, scanner as _scanner

    alive = {t.name for t in _th.enumerate()}
    badges = _sh.get_health()
    now = int(_time.time())

    # ── Upload / Flix ─────────────────────────────────────────────────────────
    upload_enabled = db.setting("UPLOAD_ENABLED", "1") == "1"
    ub = badges.get("flix", {})
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT is_ready, COUNT(*) AS n FROM files GROUP BY is_ready"
            ).fetchall()
        q = {r["is_ready"]: r["n"] for r in rows}
        upload_queue = {
            "pending":     q.get(0, 0),
            "in_progress": q.get(-2, 0),
            "uploaded":    q.get(1, 0),
            "skipped":     q.get(2, 0),
        }
        with db.conn() as c:
            last_row = c.execute(
                "SELECT filename, uploaded_at FROM files "
                "WHERE uploaded_at IS NOT NULL ORDER BY uploaded_at DESC LIMIT 1"
            ).fetchone()
        last_upload = ({"name": last_row["filename"], "ts": last_row["uploaded_at"]}
                       if last_row else None)
    except Exception:
        upload_queue = {}
        last_upload  = None

    # ── Scan / JD Indexer ─────────────────────────────────────────────────────
    scan_enabled = db.setting("SCAN_ENABLED", "1") == "1"
    sb = badges.get("jd_indexer", {})
    try:
        with db.conn() as c:
            accts = c.execute(
                "SELECT id, msisdn, label FROM accounts WHERE role='scan'"
            ).fetchall()
        active_scans = []
        for a in accts:
            st = _scanner.scan_progress(a["id"])
            if st.get("running"):
                active_scans.append({
                    "account_id":     a["id"],
                    "label":          a.get("label") or a["msisdn"],
                    "files_seen":     st.get("files_seen", 0),
                    "files_mirrored": st.get("files_mirrored", 0),
                    "started_at":     st.get("started_at"),
                    "paused":         st.get("paused", False),
                })
        with db.conn() as c:
            lr = c.execute("SELECT MAX(ts) AS last_ts FROM scan_log").fetchone()
        last_scan_ts = lr["last_ts"] if lr and lr["last_ts"] else None
    except Exception:
        accts = []
        active_scans  = []
        last_scan_ts  = None

    # ── Organizer (on-demand) ─────────────────────────────────────────────────
    organizer_enabled = db.setting("ORGANIZER_ENABLED", "1") == "1"

    return jsonify({
        "ok": True,
        "ts": now,
        "services": {
            "upload": {
                "enabled":       upload_enabled,
                "thread_alive":  "upload-watcher" in alive,
                "health_status": ub.get("status", "unknown"),
                "health_label":  ub.get("label", "…"),
                "health_ts":     ub.get("ts", 0),
                "queue":         upload_queue,
                "last_upload":   last_upload,
            },
            "scan": {
                "enabled":        scan_enabled,
                "health_status":  sb.get("status", "unknown"),
                "health_label":   sb.get("label", "…"),
                "health_ts":      sb.get("ts", 0),
                "accounts_total": len(accts),
                "active_scans":   active_scans,
                "last_scan_ts":   last_scan_ts,
            },
            "organizer": {
                "enabled":       organizer_enabled,
                "on_demand":     True,
                "health_status": "ok" if organizer_enabled else "warn",
                "health_label":  "Ready" if organizer_enabled else "Paused",
            },
        },
    })


@bp.route("/api/sapi-proxy", methods=["GET", "POST"])
@auth.login_required
def api_sapi_proxy():
    """GET: return current SAPI proxy URL.
    POST {url}: save a new SAPI proxy URL (empty string to clear)."""
    if request.method == "GET":
        return jsonify({"ok": True, "url": db.setting("JAZZDRIVE_SAPI_PROXY", "")})
    data = request.get_json(force=True, silent=True) or {}
    url  = data.get("url", "").strip()
    db.set_setting("JAZZDRIVE_SAPI_PROXY", url)
    return jsonify({"ok": True, "url": url})


@bp.route("/api/sapi-proxy/test", methods=["POST"])
@auth.login_required
def api_sapi_proxy_test():
    """Test a proxy URL specifically against the SAPI endpoint (cloud.jazzdrive.com.pk).
    Body: {url?: str}  — omit to test the currently saved SAPI proxy.
    Returns: {ok, ip, sapi_status, message}
    A 401 from SAPI means the proxy CAN reach the endpoint (key is fake — that's expected).
    A timeout/connection error means the proxy is blocked or dead."""
    import time, json as _json, base64 as _b64, urllib.parse as _up
    data = request.get_json(force=True, silent=True) or {}
    url  = data.get("url", "").strip() or db.setting("JAZZDRIVE_SAPI_PROXY", "")
    if not url:
        return jsonify({"ok": False, "message": "No proxy URL — save one first"}), 400
    proxies = {"http": url, "https": url}
    try:
        import requests as _req
        # 1. Detect external IP through proxy
        ip = "unknown"
        try:
            ip_r = _req.get("https://api.ipify.org?format=json", proxies=proxies, timeout=8)
            ip   = ip_r.json().get("ip", "?")
        except Exception:
            pass
        # 2. Hit the SAPI endpoint with a fake 40-char hex token.
        #    Expected result: 401 (proxy reached the server, but fake key rejected).
        #    Any 2xx/4xx/5xx from JazzDrive = proxy IS reaching the server = good.
        #    Connection error / timeout = proxy is dead or blocked.
        fake_at  = "a" * 40
        at_json  = _json.dumps({"data": {"accesstoken": fake_at}})
        at_b64e  = _up.quote(_b64.b64encode(at_json.encode()).decode(), safe="")
        sapi_url = (
            f"https://cloud.jazzdrive.com.pk/sapi/login/oauth"
            f"?action=login&platform=Android&keytype=accesstoken&key={at_b64e}"
        )
        t0 = time.time()
        r  = _req.get(sapi_url, proxies=proxies, timeout=15, headers={
            "User-Agent":       "Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)",
            "X-Requested-With": "com.jazz.drive",
            "Accept":           "application/json",
        })
        elapsed = round((time.time() - t0) * 1000)
        reachable = r.status_code in (200, 400, 401, 403, 500)
        return jsonify({
            "ok":          reachable,
            "ip":          ip,
            "sapi_status": r.status_code,
            "ping_ms":     elapsed,
            "message": (
                f"✔ Proxy reaches SAPI — IP={ip}, HTTP {r.status_code} ({elapsed} ms)"
                if reachable else
                f"✗ SAPI returned unexpected status {r.status_code}"
            ),
        })
    except Exception as e:
        return jsonify({"ok": False, "ip": None, "sapi_status": None,
                        "message": f"✗ {e}"})


@bp.route("/api/sapi-proxy/find", methods=["POST"])
@auth.login_required
def api_sapi_proxy_find():
    """Fetch fresh Pakistani proxies from proxylist.geonode.com API and
    test each one specifically against cloud.jazzdrive.com.pk/sapi.
    Returns the working ones sorted by ping time."""
    import concurrent.futures, json as _json, base64 as _b64, urllib.parse as _up, time
    import requests as _req

    fake_at  = "a" * 40
    at_json  = _json.dumps({"data": {"accesstoken": fake_at}})
    at_b64e  = _up.quote(_b64.b64encode(at_json.encode()).decode(), safe="")
    sapi_test_url = (
        f"https://cloud.jazzdrive.com.pk/sapi/login/oauth"
        f"?action=login&platform=Android&keytype=accesstoken&key={at_b64e}"
    )
    ua_hdr = {
        "User-Agent":       "Dalvik/2.1.0 (Linux; U; Android 12; SM-A515F Build/SP1A.210812.016)",
        "X-Requested-With": "com.jazz.drive",
        "Accept":           "application/json",
    }

    # Fetch fresh PK proxy list from geonode
    try:
        resp = _req.get(
            "https://proxylist.geonode.com/api/proxy-list"
            "?country=PK&limit=50&page=1&sort_by=lastChecked&sort_type=desc"
            "&protocols=http,https",
            timeout=15,
        )
        proxy_entries = resp.json().get("data", [])
    except Exception as fe:
        return jsonify({"ok": False, "error": f"Failed to fetch proxy list: {fe}"})

    if not proxy_entries:
        return jsonify({"ok": False, "error": "No Pakistani proxies returned by geonode"})

    def test_one(entry):
        host  = (entry.get("ip") or entry.get("host") or "").strip()
        port  = str(entry.get("port") or "")
        protos = entry.get("protocols") or ["http"]
        proto = protos[0] if protos else "http"
        url   = f"{proto}://{host}:{port}"
        p     = {"http": url, "https": url}
        try:
            ip = "?"
            try:
                ip_r = _req.get("https://api.ipify.org?format=json", proxies=p, timeout=6)
                ip   = ip_r.json().get("ip", "?")
            except Exception:
                pass
            t0 = time.time()
            r  = _req.get(sapi_test_url, proxies=p, timeout=10, headers=ua_hdr)
            ms = round((time.time() - t0) * 1000)
            ok = r.status_code in (200, 400, 401, 403, 500)
            return {"url": url, "ip": ip, "sapi_status": r.status_code,
                    "ping_ms": ms, "ok": ok}
        except Exception as e:
            return {"url": url, "ok": False, "error": str(e)[:80]}

    with concurrent.futures.ThreadPoolExecutor(max_workers=20) as ex:
        results = list(ex.map(test_one, proxy_entries[:40]))

    working = sorted([r for r in results if r.get("ok")], key=lambda x: x.get("ping_ms", 9999))
    return jsonify({
        "ok":     True,
        "tested": len(results),
        "found":  len(working),
        "working": working,
        "all":    results,
    })




# ══════════════════════════════════════════════════════════════════════════════
# SAPI Proxy Pool API — /api/pool/*
# ══════════════════════════════════════════════════════════════════════════════

@bp.route("/api/pool/list")
@auth.login_required
def pool_list():
    """List all SAPI proxies in the pool."""
    try:
        from .. import proxy_pool as _pp
        proxies = _pp.pool.list_all()
        status  = _pp.pool.current_pool_status()
        return jsonify({"ok": True, "proxies": proxies, "status": status})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/pool/add", methods=["POST"])
@auth.login_required
def pool_add():
    """Add a proxy URL to the pool (optionally test it)."""
    from .. import proxy_pool as _pp
    data = request.get_json(silent=True) or {}
    url  = (data.get("url") or "").strip()
    test = data.get("test", True)
    if not url:
        return jsonify({"ok": False, "error": "url required"}), 400
    result = _pp.pool.add_proxy(url, test=test)
    return jsonify(result)


@bp.route("/api/pool/remove/<int:proxy_id>", methods=["DELETE"])
@auth.login_required
def pool_remove(proxy_id):
    """Remove a proxy from the pool by DB id."""
    from .. import proxy_pool as _pp
    result = _pp.pool.remove_proxy(proxy_id)
    return jsonify(result)


@bp.route("/api/pool/enable/<int:proxy_id>", methods=["POST"])
@auth.login_required
def pool_enable(proxy_id):
    """Re-enable a disabled proxy (resets fail count)."""
    from .. import proxy_pool as _pp
    data = request.get_json(silent=True) or {}
    enabled = data.get("enabled", True)
    result = _pp.pool.enable_proxy(proxy_id, enabled)
    return jsonify(result)


@bp.route("/api/pool/healthcheck", methods=["POST"])
@auth.login_required
def pool_healthcheck():
    """Trigger an immediate health check of all pool proxies (async)."""
    import threading
    from .. import proxy_pool as _pp
    threading.Thread(target=_pp.pool.run_health_check_now, daemon=True).start()
    return jsonify({"ok": True, "message": "Health check started in background"})


@bp.route("/api/pool/discover", methods=["POST"])
@auth.login_required
def pool_discover():
    """Trigger an immediate discovery run — fetch + test new Pakistani proxies."""
    import threading
    from .. import proxy_pool as _pp
    def _run():
        try:
            _pp.pool.discover_new()
        except Exception:
            pass
    threading.Thread(target=_run, daemon=True).start()
    return jsonify({"ok": True, "message": "Discovery started in background"})


@bp.route("/api/pool/status")
@auth.login_required
def pool_status():
    """Quick pool health snapshot."""
    from .. import proxy_pool as _pp
    status = _pp.pool.current_pool_status()
    return jsonify({"ok": True, **status})

@bp.route("/api/app-signatures/<int:sig_id>", methods=["DELETE"])
@auth.login_required
def delete_signature(sig_id):
    try:
        with db.conn() as c:
            c.execute("DELETE FROM app_signatures WHERE id=?", (sig_id,))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# ── NEW Pool endpoints — God-Level Edition ────────────────────────────────────

@bp.route("/api/pool/stats")
@auth.login_required
def pool_stats():
    """Detailed proxy pool statistics for dashboard."""
    try:
        from .. import proxy_pool as _pp
        stats = _pp.pool.get_stats()
        return jsonify({"ok": True, "stats": stats})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/pool/bulk-import", methods=["POST"])
@auth.login_required
def pool_bulk_import():
    """Bulk import proxy URLs. Body: {urls: [str], test: bool}"""
    from .. import proxy_pool as _pp
    data = request.get_json(silent=True) or {}
    urls = data.get("urls") or []
    test = bool(data.get("test", True))
    if not isinstance(urls, list) or not urls:
        return jsonify({"ok": False, "error": "urls (list) required"}), 400
    result = _pp.pool.bulk_import(urls, test=test)
    return jsonify(result)


@bp.route("/api/pool/test/<int:proxy_id>", methods=["POST"])
@auth.login_required
def pool_test_one(proxy_id):
    """Test a single proxy by DB id and update its live stats."""
    from .. import proxy_pool as _pp
    result = _pp.pool.test_proxy_by_id(proxy_id)
    return jsonify(result)


@bp.route("/api/pool/reset-dead", methods=["POST"])
@auth.login_required
def pool_reset_dead():
    """Re-enable all disabled proxies and queue for fast-recovery re-test."""
    from .. import proxy_pool as _pp
    result = _pp.pool.reset_dead()
    return jsonify(result)


@bp.route("/api/pool/export")
@auth.login_required
def pool_export():
    """Export full proxy URL list as plain text list."""
    from .. import proxy_pool as _pp
    urls = _pp.pool.export_list()
    return jsonify({"ok": True, "urls": urls, "count": len(urls)})
