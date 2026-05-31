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
    if proxies_json:
        try:
            proxies = json.loads(proxies_json)
        except:
            proxies = []
    else:
        # Seed default Pakistani proxies
        proxies = [
            {"url": "http://103.141.144.116:8080", "status": "untested"},
            {"url": "http://202.141.240.26:8080", "status": "untested"},
            {"url": "http://111.119.160.18:8080", "status": "untested"},
            {"url": "http://103.255.5.110:8080", "status": "untested"},
            {"url": "http://111.119.178.131:8080", "status": "untested"},
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


@bp.route("/api/app-signatures/<int:sig_id>", methods=["DELETE"])
@auth.login_required
def delete_signature(sig_id):
    try:
        with db.conn() as c:
            c.execute("DELETE FROM app_signatures WHERE id=?", (sig_id,))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500
