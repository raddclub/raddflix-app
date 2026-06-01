"""WhatsApp + Telegram bot control — full lifecycle, QR, users, logs, send."""
from flask import Blueprint, render_template, jsonify, request
from .. import auth, config, db

# Canonical bot directory — must match hub/bots/whatsapp.py V2_BOT_DIR
try:
    from ..bots.whatsapp import V2_BOT_DIR as _WA_BOT_DIR
except Exception:
    _WA_BOT_DIR = config.PROJECT_ROOT.parent / "RaddHub-v2.0" / "whatsapp-bot"

bp = Blueprint("bots", __name__)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _bot_enabled(key: str) -> bool:
    """Read ENABLE_* flag from DB first (admin-persisted), fall back to env var.
    DB value wins so the admin toggle survives server restarts without editing .env.
    """
    try:
        v = db.setting(key)
        if v is not None:
            return str(v).strip().lower() in ("1", "true", "yes", "on")
    except Exception:
        pass
    return config.get_env_bool(key, False)


# ---------------------------------------------------------------------------
# Pages
# ---------------------------------------------------------------------------

@bp.route("/")
@auth.login_required
def page():
    return render_template("bots.html",
        whatsapp_enabled=_bot_enabled("ENABLE_WHATSAPP_BOT"),
        telegram_enabled=_bot_enabled("ENABLE_TELEGRAM_BOT"),
    )


# ---------------------------------------------------------------------------
# Combined status
# ---------------------------------------------------------------------------

@bp.route("/api/status")
@auth.login_required
def status():
    wa = {"enabled": _bot_enabled("ENABLE_WHATSAPP_BOT")}
    tg = {"enabled": _bot_enabled("ENABLE_TELEGRAM_BOT")}
    try:
        from ..bots.whatsapp import get_status as _wa_status
        wa.update(_wa_status())
    except Exception as e:
        wa["error"] = str(e)
    try:
        from ..bots import telegram as _tg
        tg.update(_tg.get_status())
    except Exception as e:
        tg["error"] = str(e)
    return jsonify({"whatsapp": wa, "telegram": tg})


# ---------------------------------------------------------------------------
# Enable / Disable toggle  (single endpoint for both bots)
# ---------------------------------------------------------------------------

@bp.route("/api/toggle", methods=["POST"])
@auth.login_required
def toggle_bot():
    """Enable or disable a bot. Body: {service: "whatsapp"|"telegram", enabled: bool}
    When disabling, the running process is stopped automatically.
    State is persisted to DB so it survives server restarts.
    """
    data    = request.get_json(silent=True) or {}
    service = (data.get("service") or "").strip().lower()
    enabled = bool(data.get("enabled", False))

    key_map = {
        "whatsapp": "ENABLE_WHATSAPP_BOT",
        "telegram": "ENABLE_TELEGRAM_BOT",
    }
    if service not in key_map:
        return jsonify({"ok": False, "error": "Unknown service — use 'whatsapp' or 'telegram'"}), 400

    db.set_setting(key_map[service], "1" if enabled else "0")

    # Auto-stop when disabling so no orphan process runs while marked disabled
    stop_result = None
    if not enabled:
        try:
            if service == "whatsapp":
                from ..bots.whatsapp import stop as _wa_stop
                stop_result = _wa_stop()
            elif service == "telegram":
                from ..bots import telegram as _tg
                stop_result = _tg.stop()
        except Exception as e:
            stop_result = {"ok": False, "error": str(e)}

    return jsonify({
        "ok": True,
        "service": service,
        "enabled": enabled,
        "stop_result": stop_result,
    })


# ===========================================================================
# WhatsApp endpoints
# ===========================================================================

@bp.route("/api/whatsapp/status")
@auth.login_required
def wa_status():
    try:
        from ..bots.whatsapp import get_status
        return jsonify(get_status())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/start", methods=["POST"])
@auth.login_required
def wa_start():
    if not _bot_enabled("ENABLE_WHATSAPP_BOT"):
        return jsonify({"ok": False, "error": "WhatsApp bot is disabled. Enable it first."}), 403
    try:
        from ..bots.whatsapp import start
        return jsonify(start())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/stop", methods=["POST"])
@auth.login_required
def wa_stop():
    try:
        from ..bots.whatsapp import stop
        return jsonify(stop())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/restart", methods=["POST"])
@auth.login_required
def wa_restart():
    if not _bot_enabled("ENABLE_WHATSAPP_BOT"):
        return jsonify({"ok": False, "error": "WhatsApp bot is disabled. Enable it first."}), 403
    try:
        from ..bots.whatsapp import restart
        return jsonify(restart())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/logs")
@auth.login_required
def wa_logs():
    n = int(request.args.get("n", 100))
    try:
        from ..bots.whatsapp import get_logs
        return jsonify({"ok": True, "lines": get_logs(n)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "lines": []}), 500


@bp.route("/api/whatsapp/qr")
@auth.login_required
def wa_qr():
    try:
        from ..bots.whatsapp import get_status, QR_PNG
        st = get_status()
        return jsonify({
            "ok": True,
            "connected":    st.get("connected", False),
            "running":      st.get("running",   False),
            "qr_available": QR_PNG.exists() if hasattr(QR_PNG, "exists") else False,
            "pairing_code": st.get("pairing_code"),
            "phone":        st.get("phone", ""),
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/qr.png")
@auth.login_required
def wa_qr_png():
    try:
        from flask import send_file
        from ..bots.whatsapp import QR_PNG
        if not QR_PNG.exists():
            return ("", 404)
        return send_file(str(QR_PNG), mimetype="image/png", max_age=0)
    except Exception:
        return ("", 404)


@bp.route("/api/whatsapp/pair", methods=["POST"])
@auth.login_required
def wa_pair():
    data  = request.get_json(silent=True) or {}
    phone = data.get("phone", "").strip()
    try:
        from ..bots.whatsapp import request_pairing_code
        return jsonify(request_pairing_code(phone))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/relink", methods=["POST"])
@auth.login_required
def wa_relink():
    """Force re-link (wipe auth + restart)."""
    try:
        from ..bots.whatsapp import relink
        return jsonify(relink())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/send", methods=["POST"])
@auth.login_required
def wa_send():
    """Send a message to a JID. Body: {jid, message}"""
    data = request.get_json(silent=True) or {}
    jid  = data.get("jid", "").strip()
    msg  = data.get("message", "").strip()
    if not jid or not msg:
        return jsonify({"ok": False, "error": "jid and message required"}), 400
    try:
        from ..bots.whatsapp import send_message
        return jsonify(send_message(jid, msg))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/users")
@auth.login_required
def wa_users():
    """List WhatsApp bot users from users.json."""
    try:
        from pathlib import Path
        import json
        _BOT_DIR   = _WA_BOT_DIR
        _BOT_USERS = _BOT_DIR / "users.json"
        d = json.loads(_BOT_USERS.read_text()) if _BOT_USERS.exists() else {"admins": [], "verified": [], "blocked": []}
        return jsonify({"ok": True, "users": d})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "users": {}}), 500


@bp.route("/api/whatsapp/users/add", methods=["POST"])
@auth.login_required
def wa_users_add():
    data = request.get_json(silent=True) or {}
    role = data.get("role", "verified")
    num  = "".join(c for c in str(data.get("number", "")) if c.isdigit())
    if not num or role not in ("admins", "verified", "blocked"):
        return jsonify({"ok": False, "error": "bad role or number"}), 400
    try:
        from pathlib import Path
        import json
        _BOT_DIR   = _WA_BOT_DIR
        _BOT_USERS = _BOT_DIR / "users.json"
        d = json.loads(_BOT_USERS.read_text()) if _BOT_USERS.exists() else {"admins": [], "verified": [], "blocked": []}
        jid = f"{num}@s.whatsapp.net"
        arr = d.setdefault(role, [])
        if not any("".join(c for c in x if c.isdigit()) == num for x in arr):
            arr.append(jid)
        if role == "verified":
            d["blocked"] = [x for x in d.get("blocked", []) if "".join(c for c in x if c.isdigit()) != num]
        _BOT_DIR.mkdir(parents=True, exist_ok=True)
        _BOT_USERS.write_text(json.dumps(d, indent=2))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/whatsapp/users/remove", methods=["POST"])
@auth.login_required
def wa_users_remove():
    data = request.get_json(silent=True) or {}
    role = data.get("role", "verified")
    num  = "".join(c for c in str(data.get("number", "")) if c.isdigit())
    if not num or role not in ("admins", "verified", "blocked"):
        return jsonify({"ok": False, "error": "bad role or number"}), 400
    try:
        from pathlib import Path
        import json
        _BOT_DIR   = _WA_BOT_DIR
        _BOT_USERS = _BOT_DIR / "users.json"
        d = json.loads(_BOT_USERS.read_text()) if _BOT_USERS.exists() else {}
        d[role] = [x for x in d.get(role, []) if "".join(c for c in x if c.isdigit()) != num]
        _BOT_USERS.write_text(json.dumps(d, indent=2))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ===========================================================================
# Telegram endpoints
# ===========================================================================

@bp.route("/api/telegram/status")
@auth.login_required
def tg_status():
    try:
        from ..bots import telegram as _tg
        return jsonify(_tg.get_status())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/telegram/start", methods=["POST"])
@auth.login_required
def tg_start():
    if not _bot_enabled("ENABLE_TELEGRAM_BOT"):
        return jsonify({"ok": False, "error": "Telegram bot is disabled. Enable it first."}), 403
    try:
        from ..bots import telegram as _tg
        return jsonify(_tg.start())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/telegram/stop", methods=["POST"])
@auth.login_required
def tg_stop():
    try:
        from ..bots import telegram as _tg
        return jsonify(_tg.stop())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/telegram/restart", methods=["POST"])
@auth.login_required
def tg_restart():
    if not _bot_enabled("ENABLE_TELEGRAM_BOT"):
        return jsonify({"ok": False, "error": "Telegram bot is disabled. Enable it first."}), 403
    try:
        from ..bots import telegram as _tg
        return jsonify(_tg.restart())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/telegram/logs")
@auth.login_required
def tg_logs():
    n = int(request.args.get("n", 100))
    try:
        from ..bots import telegram as _tg
        return jsonify({"ok": True, "lines": _tg.get_logs(n)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "lines": []}), 500
