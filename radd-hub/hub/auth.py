"""Simple admin login (single user from env or vault)."""
from __future__ import annotations
import os
import time
from functools import wraps
from flask import session, request, redirect, url_for, jsonify, render_template_string


def admin_creds() -> tuple[str, str]:
    return (os.environ.get("RADD_ADMIN_USER", "admin"),
            os.environ.get("RADD_ADMIN_PASS", ""))


ADMIN_SESSION_TTL = 8 * 3600  # 8 hours idle timeout — enforced on every request

def is_logged_in() -> bool:
    if not session.get("admin"):
        return False
    last = session.get("admin_last", 0)
    if time.time() - last > ADMIN_SESSION_TTL:
        session.clear()
        return False
    session["admin_last"] = time.time()
    return True


import logging
log = logging.getLogger("hub.auth")

def _bot_key_ok() -> bool:
    """Return True if the request carries a valid internal bot API key."""
    key = os.environ.get("BOT_API_KEY", "")
    req_key = request.headers.get("X-Bot-Key")
    
    # Also allow JazzBuzz app bypass for development
    jb_key = os.environ.get("JAZZBUZZ_KEY", "")  # No hardcoded fallback — must be set explicitly
    req_jb_key = request.headers.get("X-JazzBuzz-Key")
    
    log.debug("_bot_key_ok: env_key=%s... req_key=%s...", key[:5] if key else "None", req_key[:5] if req_key else "None")
    
    if key and req_key == key:
        return True
    if jb_key and req_jb_key == jb_key:
        return True
    return False


def login_required(fn):
    @wraps(fn)
    def wrapper(*a, **kw):
        # Allow internal bot-to-hub calls authenticated by pre-shared key
        ok = _bot_key_ok()
        log.debug("login_required: path=%s bot_key_ok=%s", request.path, ok)
        if ok:
            return fn(*a, **kw)
        if not is_logged_in():
            if request.path.startswith("/api/"):
                return jsonify({"error": "auth required"}), 401
            return redirect(url_for("auth.login", next=request.path))
        return fn(*a, **kw)
    return wrapper




import hashlib as _hashlib
import os as _os

def _csrf_secret() -> str:
    return _os.environ.get("SESSION_SECRET") or _os.environ.get("FLASK_SECRET_KEY") or "csrf-fallback"

def get_csrf_token() -> str:
    """Return a per-session CSRF token (generate if absent)."""
    from flask import session
    if "csrf_token" not in session:
        session["csrf_token"] = _os.urandom(24).hex()
    return session["csrf_token"]

def validate_csrf() -> bool:
    """Validate CSRF token from form or header. Returns True if valid."""
    from flask import session
    expected = session.get("csrf_token")
    if not expected:
        return False
    submitted = (
        request.form.get("_csrf_token") or
        request.headers.get("X-CSRF-Token") or
        ""
    )
    return _hashlib.compare_digest(expected, submitted) if submitted else False

def csrf_protect(fn):
    """Decorator: validates CSRF token on POST/PUT/DELETE requests.
    Skip validation for API routes (they use Bearer tokens instead).
    """
    from functools import wraps
    @wraps(fn)
    def wrapper(*a, **kw):
        if request.method in ("POST", "PUT", "DELETE", "PATCH"):
            # API routes use Bearer tokens — skip CSRF
            if request.path.startswith("/api/"):
                return fn(*a, **kw)
            if not validate_csrf():
                log.warning("CSRF validation failed: path=%s ip=%s", request.path, request.remote_addr)
                from flask import abort
                abort(403)
        return fn(*a, **kw)
    return wrapper

from flask import Blueprint
bp = Blueprint("auth", __name__)


_LOGIN_HTML = """<!doctype html><html><head><meta charset=utf-8>
<title>Sign in - Radd Hub</title><meta name=viewport content="width=device-width,initial-scale=1">
<style>body{background:#0a0c11;color:#e7eaf2;font-family:system-ui;display:grid;place-items:center;min-height:100vh;margin:0}
.card{background:#12151e;border:1px solid #252d3d;padding:32px;border-radius:14px;width:340px}
h1{margin:0 0 18px;font-size:20px}
input{width:100%;padding:11px 12px;margin:6px 0;background:#181d28;border:1px solid #252d3d;color:#e7eaf2;border-radius:8px;font-size:14px}
button{width:100%;padding:11px;margin-top:14px;background:#7c5cff;color:white;border:none;border-radius:8px;font-weight:600;cursor:pointer;font-size:14px}
.err{color:#ff6b6b;margin:6px 0;font-size:13px}
.tip{color:#7e859b;font-size:12px;margin-top:14px}</style></head><body>
<form class=card method=post>
<h1>Sign in to Radd Hub</h1>
{% if error %}<div class=err>{{ error }}</div>{% endif %}
<input name=username placeholder=Username value=admin autofocus>
<input name=password type=password placeholder=Password>
<button>Sign in</button>
<div class=tip>Admin password was generated on first run.<br>Find it in your <code>.env</code> file (RADD_ADMIN_PASS).</div>
</form></body></html>"""


@bp.route("/login", methods=["GET", "POST"])
def login():
    err = None
    if request.method == "POST":
        u = (request.form.get("username") or "").strip()
        p = (request.form.get("password") or "").strip()

        # Brute-force protection: lockout after 10 failures per IP
        import time as _time
        _ip = request.remote_addr or "unknown"
        _lock_key = f"admin_login:{_ip}"
        _now = _time.time()

        # Check if IP is locked
        if not hasattr(login, "_fail_store"):
            login._fail_store = {}
        _fails = [t for t in login._fail_store.get(_lock_key, []) if _now - t < 900]
        if len(_fails) >= 10:
            remaining = int(900 - (_now - min(_fails)))
            err = f"Too many failed attempts. Try again in {remaining//60+1} min."
            return render_template_string(_LOGIN_HTML, error=err)

        au, ap = admin_creds()
        # Constant-time comparison to prevent timing attacks
        import hmac as _hmac
        u_ok = _hmac.compare_digest(u, au)
        p_ok = _hmac.compare_digest(p, ap) if ap else False
        if u_ok and p_ok:
            login._fail_store.pop(_lock_key, None)
            session.clear()
            session["admin"] = u
            session["admin_last"] = time.time()
            session.permanent = True
            return redirect(request.args.get("next") or "/")
        # Record failure
        _fails.append(_now)
        login._fail_store[_lock_key] = _fails
        log.warning("Admin login failed: ip=%s user=%s attempt=%d", _ip, u[:20], len(_fails))
        err = "Invalid credentials"
    return render_template_string(_LOGIN_HTML, error=err)


@bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
