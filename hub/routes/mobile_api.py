"""Mobile app authentication & subscription API endpoints.

Serves:
  /api/auth/*          — register, login, guest, refresh, logout, me, device-bind
  /api/subscription/*  — plans, status, tid submit/status
  /api/usage/*         — log bytes, get quota
  /api/payment-methods — enabled payment gateways
  /api/notifications/* — push notification inbox
  /api/history/*       — watch history

JWT authentication (HS256, signed with SESSION_SECRET):
  Access token  — 15-min lifetime
  Refresh token — 90-day lifetime, hash stored in app_refresh_tokens

Device binding (Phase 5):
  app_users.device_id = first device that logged in
  Login from a different device returns 409 {"error": "device_conflict"}
  Admin resets via /app-users panel
"""
from __future__ import annotations
import base64 as _b64
import hashlib
try:
    import bcrypt as _bcrypt
except ImportError:
    _bcrypt = None  # bcrypt not installed — password hashing will fall back to legacy
import hmac as _hmac
import json
import logging
import os
import sqlite3
import time
from functools import wraps
from typing import Optional

from flask import Blueprint, jsonify, request

from .. import db

log = logging.getLogger("hub.mobile_api")
_EMERGENCY_SECRET: Optional[str] = None  # BUG-A32: per-process random last-resort JWT secret

# ── Login rate limiting (DB-backed per-IP) ───────────────────────────────────
_login_ip_window: dict = {}   # ip → list[float] — in-memory cache layer
_LOGIN_RATE_WINDOW = 900      # 15-minute sliding window
_LOGIN_RATE_MAX    = 10       # max attempts per window per IP

# BUG-S14 fix: also persist to DB so rate limit survives server restarts
_RATE_TABLE_DDL = (
    "CREATE TABLE IF NOT EXISTS login_rate_log "
    "(ip TEXT NOT NULL, ts REAL NOT NULL)"
)
_rate_table_ok = False

def _ensure_rate_table() -> None:
    global _rate_table_ok
    if _rate_table_ok:
        return
    try:
        with db.conn() as _c:
            _c.execute(_RATE_TABLE_DDL)
            _c.execute("CREATE INDEX IF NOT EXISTS idx_lrl_ip ON login_rate_log(ip)")
        _rate_table_ok = True
    except Exception:
        pass


def _login_rate_check(ip: str) -> bool:
    """Return True (allowed) or False (rate-limited).
    Checks in-memory window first (fast path), then DB for cross-restart persistence.
    BUG-S14 fix: DB-backed so limits survive server restarts.
    """
    import time as _t
    now  = _t.time()
    cutoff = now - _LOGIN_RATE_WINDOW

    # Fast in-memory path
    hits = _login_ip_window.get(ip, [])
    hits = [t for t in hits if t > cutoff]

    # Merge from DB (catches attempts from before last restart)
    _ensure_rate_table()
    try:
        with db.conn() as _c:
            rows = _c.execute(
                "SELECT ts FROM login_rate_log WHERE ip=? AND ts>?", (ip, cutoff)
            ).fetchall()
            db_hits = {r["ts"] for r in rows}
            # Merge without duplicating in-memory entries
            all_ts = sorted(set(hits) | db_hits)
    except Exception:
        all_ts = hits

    if len(all_ts) >= _LOGIN_RATE_MAX:
        _login_ip_window[ip] = all_ts
        return False

    all_ts.append(now)
    _login_ip_window[ip] = all_ts
    # Persist new attempt to DB (best-effort)
    try:
        with db.conn() as _c:
            _c.execute("INSERT INTO login_rate_log(ip,ts) VALUES(?,?)", (ip, now))
            # Prune old rows from DB (keep it small)
            _c.execute("DELETE FROM login_rate_log WHERE ts<?", (cutoff,))
    except Exception:
        pass
    # Prune stale IPs from in-memory dict every ~100 new IPs
    if len(_login_ip_window) > 500:
        stale = [k for k, v in list(_login_ip_window.items())
                 if not any(t > cutoff for t in v)]
        for k in stale:
            del _login_ip_window[k]
    return True

# ── JWT helpers ────────────────────────────────────────────────────────────

def _secret() -> str:
    """JWT signing secret. Priority: SESSION_SECRET env -> FLASK_SECRET_KEY env
    -> DB-persisted random key (generated once, survives server restarts).
    BUG-A32 fix: secret no longer a predictable hardcoded fallback.
    """
    env_val = (os.environ.get("SESSION_SECRET") or os.environ.get("FLASK_SECRET_KEY"))
    if env_val and len(env_val) >= 16:
        return env_val
    try:
        with db.conn() as _c:
            row = _c.execute(
                "SELECT v FROM settings WHERE k='mobile_jwt_secret'"
            ).fetchone()
            if row and row["v"]:
                return row["v"]
            import secrets as _sec
            generated = _sec.token_hex(32)
            _c.execute(
                "INSERT OR IGNORE INTO settings(k,v) VALUES('mobile_jwt_secret',?)",
                (generated,)
            )
            row2 = _c.execute(
                "SELECT v FROM settings WHERE k='mobile_jwt_secret'"
            ).fetchone()
            return row2["v"] if row2 else generated
    except Exception:
        # Last resort: generate a per-process random secret (not persistent, but not
        # a predictable static string). Tokens issued here are invalidated on restart.
        global _EMERGENCY_SECRET
        if _EMERGENCY_SECRET is None:
            import secrets as _sec
            _EMERGENCY_SECRET = _sec.token_hex(32)
            log.warning("_secret(): DB unavailable — using per-process emergency secret")
        return _EMERGENCY_SECRET

def _b64url_encode(data: bytes) -> str:
    return _b64.urlsafe_b64encode(data).rstrip(b"=").decode()

def _b64url_decode(s: str) -> bytes:
    s += "=" * ((4 - len(s) % 4) % 4)
    return _b64.urlsafe_b64decode(s)

def _make_jwt(payload: dict, lifetime_s: int) -> str:
    header = _b64url_encode(b'{"alg":"HS256","typ":"JWT"}')
    payload = dict(payload)
    payload["exp"] = int(time.time()) + lifetime_s
    body   = _b64url_encode(json.dumps(payload, separators=(",", ":")).encode())
    sig_input = f"{header}.{body}".encode()
    sig    = _hmac.new(_secret().encode(), sig_input, hashlib.sha256).digest()
    return f"{header}.{body}.{_b64url_encode(sig)}"

def _verify_jwt(token: str) -> Optional[dict]:
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return None
        header, body, sig = parts
        sig_input = f"{header}.{body}".encode()
        expected  = _hmac.new(_secret().encode(), sig_input, hashlib.sha256).digest()
        actual    = _b64url_decode(sig)
        if not _hmac.compare_digest(expected, actual):
            return None
        payload = json.loads(_b64url_decode(body))
        if payload.get("exp", 0) < time.time():
            return None
        return payload
    except Exception:
        return None

def _access_token(user_id: int, phone: str) -> str:
    return _make_jwt({"sub": user_id, "phone": phone, "type": "access"}, 900)

def _refresh_token_jwt(user_id: int, device_id: str) -> str:
    return _make_jwt({"sub": user_id, "type": "refresh", "device": device_id}, 7_776_000)

def _hash_password(pw: str) -> str:
    """Legacy SHA-256 hash — used for OTP codes only (deterministic comparison needed).
    For user passwords, use _hash_user_password() / _verify_user_password().
    """
    return hashlib.sha256(pw.encode()).hexdigest()

def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()

# ── Bcrypt user-password helpers (P1.3 security fix) ─────────────────────────

def _hash_user_password(pw: str) -> str:
    """Hash a user password with bcrypt (salted, one-way). Use for registration."""
    if _bcrypt is None:
        # Fallback if bcrypt not installed (should not happen in production)
        log.error("bcrypt not available — falling back to SHA-256. Install bcrypt!")
        return hashlib.sha256(pw.encode()).hexdigest()
    return _bcrypt.hashpw(pw.encode(), _bcrypt.gensalt()).decode()

def _verify_user_password(pw: str, stored_hash: str) -> bool:
    """Verify a user password.

    Handles:
      - Modern bcrypt hashes ($2b$ / $2a$) — full bcrypt verify
      - Legacy unsalted SHA-256 (40-char hex) — migration path: verifies
        with SHA-256 so existing users can still log in; caller should
        re-hash and store the bcrypt hash immediately after.
    """
    if stored_hash.startswith(("$2b$", "$2a$")):
        if _bcrypt is None:
            return False
        try:
            return _bcrypt.checkpw(pw.encode(), stored_hash.encode())
        except Exception:
            return False
    # Legacy SHA-256 (no salt) — migration path
    return hashlib.sha256(pw.encode()).hexdigest() == stored_hash

def _migrate_password_hash(user_id: int, plaintext_pw: str) -> None:
    """Silently upgrade a legacy SHA-256 hash to bcrypt after successful login."""
    try:
        new_hash = _hash_user_password(plaintext_pw)
        with db.conn() as _mc:
            _mc.execute("UPDATE app_users SET password_hash=? WHERE id=?",
                        (new_hash, user_id))
        log.info("password_migrated user_id=%s sha256→bcrypt", user_id)
    except Exception as _e:
        log.warning("password_migration_failed user_id=%s: %s", user_id, _e)

def _require_auth(fn):
    """Decorator: validate Bearer access token; injects _user_id and _phone."""
    @wraps(fn)
    def wrapper(*a, **kw):
        auth_header = request.headers.get("Authorization", "")
        if not auth_header.startswith("Bearer "):
            return jsonify({"error": "auth required"}), 401
        token   = auth_header[7:]
        payload = _verify_jwt(token)
        if not payload or payload.get("type") != "access":
            return jsonify({"error": "invalid or expired token"}), 401
        # Guest tokens (sub=0) are valid but have limited access
        kw["_user_id"] = int(payload["sub"])
        kw["_phone"]   = payload.get("phone", "")
        return fn(*a, **kw)
    return wrapper

# ── Blueprints ─────────────────────────────────────────────────────────────
bp_auth  = Blueprint("mobile_auth",  __name__)
bp_sub   = Blueprint("mobile_sub",   __name__)
bp_usage = Blueprint("mobile_usage", __name__)
bp_pay   = Blueprint("mobile_pay",   __name__)
bp_notif = Blueprint("mobile_notif", __name__)
bp_hist  = Blueprint("mobile_hist",  __name__)

# ── Auth ───────────────────────────────────────────────────────────────────

@bp_auth.route("/register", methods=["POST"])
def register():
    data     = request.get_json(silent=True) or {}
    phone    = _normalize_phone((data.get("phone") or "").strip())
    password = (data.get("password") or "").strip()
    if not phone or not password:
        return jsonify({"error": "phone and password required"}), 400
    if len(password) < 6:
        return jsonify({"error": "password must be at least 6 characters"}), 400
    pw_hash = _hash_user_password(password)
    now     = int(time.time())
    try:
        with db.conn() as c:
            c.execute(
                "INSERT INTO app_users(phone, password_hash, created_at) VALUES(?,?,?)",
                (phone, pw_hash, now)
            )
        return jsonify({"ok": True, "message": "Account created. Please log in."})
    except sqlite3.IntegrityError:
        # BUG-S08 fix: catch UNIQUE constraint atomically instead of check-then-insert
        return jsonify({"error": "Phone already registered"}), 409
    except Exception as e:
        log.error("register error: %s", e)
        return jsonify({"error": "Registration failed"}), 500


@bp_auth.route("/login", methods=["POST"])
def login():
    data        = request.get_json(silent=True) or {}
    phone       = _normalize_phone((data.get("phone") or "").strip())
    password    = (data.get("password") or "").strip()
    device_id   = (data.get("device_id") or "").strip()
    device_name = (data.get("device_name") or "Android Device").strip()

    if not phone or not password:
        return jsonify({"error": "phone and password required"}), 400

    # Rate-limit login attempts per IP (BUG-N06)
    _ip = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown")
    _ip = _ip.split(",")[0].strip()
    if not _login_rate_check(_ip):
        return jsonify({"error": "Too many login attempts. Please try again later."}), 429

    now = int(time.time())

    with db.conn() as c:
        # Fetch by phone only — password verified in Python (supports bcrypt + legacy)
        _urow = c.execute(
            "SELECT * FROM app_users WHERE phone=?", (phone,)
        ).fetchone()
        if not _urow or not _verify_user_password(password, _urow["password_hash"]):
            return jsonify({"error": "Invalid phone or password"}), 401
        user = dict(_urow)
        # Silently migrate legacy SHA-256 → bcrypt on every successful login
        if not user["password_hash"].startswith(("$2b$", "$2a$")):
            _migrate_password_hash(user["id"], password)
        if not user.get("is_active", 1):
            return jsonify({"error": "Account suspended. Contact support."}), 403

        # ── Phase 5: Device binding enforcement ────────────────────────────
        bound_device = user.get("device_id")
        if device_id:
            if bound_device and bound_device != device_id:
                # A different device is already bound — return 409
                log.warning(
                    "device_conflict: user_id=%s bound=%s... attempted=%s...",
                    user["id"], bound_device[:8], device_id[:8]
                )
                return jsonify({
                    "error":             "device_conflict",
                    "message":           (
                        "This account is active on another device. "
                        "Contact support on WhatsApp to switch devices."
                    ),
                    "bound_device_name": user.get("device_name") or "Another Device",
                }), 409
            if not bound_device:
                # First login — bind this device
                c.execute(
                    "UPDATE app_users SET device_id=?, device_name=?, device_bound_at=? WHERE id=?",
                    (device_id, device_name, now, user["id"])
                )
                user["device_id"] = device_id

        # Update last_login_at
        c.execute("UPDATE app_users SET last_login_at=? WHERE id=?", (now, user["id"]))

    # Issue tokens
    access  = _access_token(user["id"], phone)
    refresh = _refresh_token_jwt(user["id"], device_id)
    refresh_hash = _hash_token(refresh)

    with db.conn() as c:
        # Replace any existing refresh token for this device
        c.execute(
            "UPDATE app_refresh_tokens SET revoked=1 WHERE user_id=? AND device_id=?",
            (user["id"], device_id)
        )
        c.execute(
            "INSERT INTO app_refresh_tokens(user_id, token_hash, device_id, expires_at) "
            "VALUES(?,?,?,?)",
            (user["id"], refresh_hash, device_id, now + 7_776_000)
        )

    return jsonify({
        "ok":            True,
        "access_token":  access,
        "refresh_token": refresh,
        "user_id":       user["id"],
        "phone":         phone,
        "user": {
            "id":    user["id"],
            "phone": phone,
            "plan":  _get_plan(user["id"]),
        },
    })


@bp_auth.route("/guest", methods=["POST"])
def guest():
    token = _make_jwt(
        {"sub": 0, "phone": "guest", "type": "access", "guest": True},
        86_400  # 24h
    )
    return jsonify({"ok": True, "access_token": token})


@bp_auth.route("/refresh", methods=["POST"])
def refresh_token():
    data  = request.get_json(silent=True) or {}
    token = (data.get("refresh_token") or "").strip()
    if not token:
        return jsonify({"error": "refresh_token required"}), 400
    payload = _verify_jwt(token)
    if not payload or payload.get("type") != "refresh":
        return jsonify({"error": "invalid or expired refresh token"}), 401
    token_hash = _hash_token(token)
    with db.conn() as c:
        row = c.execute(
            "SELECT * FROM app_refresh_tokens "
            "WHERE token_hash=? AND revoked=0 AND expires_at>?",
            (token_hash, int(time.time()))
        ).fetchone()
        if not row:
            return jsonify({"error": "refresh token revoked or expired"}), 401
        user = c.execute(
            "SELECT * FROM app_users WHERE id=?", (row["user_id"],)
        ).fetchone()
        if not user or not user["is_active"]:
            return jsonify({"error": "account not found or suspended"}), 401
    user = dict(user)
    new_access = _access_token(user["id"], user["phone"])
    return jsonify({
        "ok":           True,
        "access_token": new_access,
        "user_id":      user["id"],
    })


@bp_auth.route("/logout", methods=["POST"])
def logout():
    data  = request.get_json(silent=True) or {}
    token = (data.get("refresh_token") or "").strip()
    if token:
        token_hash = _hash_token(token)
        with db.conn() as c:
            c.execute(
                "UPDATE app_refresh_tokens SET revoked=1 WHERE token_hash=?",
                (token_hash,)
            )
    return jsonify({"ok": True})




# ── OTP Device Switch ────────────────────────────────────────────────────────

@bp_auth.route("/device-switch/request", methods=["POST"])
def device_switch_request():
    """POST /api/auth/device-switch/request
    Body: {"phone": "03001234567"}
    Generates a 6-digit OTP, stores the hash+expiry in settings, and sends
    the code via WhatsApp.  Responds identically whether or not the phone is
    registered (avoids user-enumeration).
    """
    data  = request.get_json(silent=True) or {}
    phone = _normalize_phone((data.get("phone") or "").strip())
    if not phone:
        return jsonify({"error": "phone required"}), 400

    with db.conn() as c:
        user = c.execute("SELECT id FROM app_users WHERE phone=?", (phone,)).fetchone()

    if user:
        import secrets as _sec
        otp       = str(_sec.randbelow(1_000_000)).zfill(6)
        otp_hash  = _hash_password(otp)
        expires   = int(time.time()) + 600   # 10-minute validity
        with db.conn() as c:
            c.execute(
                "INSERT OR REPLACE INTO settings(k, v) VALUES(?, ?)",
                (f"dsw_otp_{phone}", f"{otp_hash}:{expires}")
            )
        _send_whatsapp_otp(phone, (
            f"RaddFlix: Your device switch code is *{otp}*. "
            "Valid for 10 minutes. Never share this code. "
            "If you did not request this, contact support."
        ))
        log.info("device_switch_request: OTP generated for phone %s…", phone[:5])

    return jsonify({"ok": True, "message": "If this phone is registered, an OTP will be sent."})


@bp_auth.route("/device-switch/verify", methods=["POST"])
def device_switch_verify():
    """POST /api/auth/device-switch/verify
    Body: {"phone":"03001234567","otp_code":"123456","device_id":"...","device_name":"..."}
    Verifies the OTP, unbinds the old device, binds the new one, returns fresh tokens.
    """
    data        = request.get_json(silent=True) or {}
    phone       = _normalize_phone((data.get("phone")       or "").strip())
    otp_code    = str(data.get("otp_code") or "").strip()
    device_id   = (data.get("device_id")   or "").strip()
    device_name = (data.get("device_name") or "Android Device").strip()

    if not phone or not otp_code or not device_id:
        return jsonify({"error": "phone, otp_code, and device_id required"}), 400

    with db.conn() as c:
        row = c.execute(
            "SELECT v FROM settings WHERE k=?", (f"dsw_otp_{phone}",)
        ).fetchone()

    if not row or not row["v"]:
        return jsonify({"error": "No OTP found for this number. Request a new one."}), 400

    parts = (row["v"] or "").split(":", 1)
    if len(parts) != 2:
        return jsonify({"error": "Corrupted OTP record. Request a new one."}), 400

    stored_hash, expires_str = parts
    if int(time.time()) > int(expires_str):
        return jsonify({"error": "OTP has expired. Please request a new one."}), 400

    if not _hmac.compare_digest(stored_hash, _hash_password(otp_code)):
        return jsonify({"error": "Incorrect OTP. Check the code and try again."}), 401

    # OTP valid — reset device and issue fresh tokens
    now = int(time.time())
    with db.conn() as c:
        user = c.execute("SELECT * FROM app_users WHERE phone=?", (phone,)).fetchone()
        if not user or not user["is_active"]:
            return jsonify({"error": "Account not found or suspended."}), 404
        user = dict(user)
        # Bind new device
        c.execute(
            "UPDATE app_users SET device_id=?, device_name=?, device_bound_at=?, "
            "last_login_at=? WHERE id=?",
            (device_id, device_name, now, now, user["id"])
        )
        # Revoke all existing refresh tokens (old device loses access immediately)
        c.execute(
            "UPDATE app_refresh_tokens SET revoked=1 WHERE user_id=?", (user["id"],)
        )
        # Consume the OTP (single-use)
        c.execute("DELETE FROM settings WHERE k=?", (f"dsw_otp_{phone}",))

    access       = _access_token(user["id"], phone)
    refresh      = _refresh_token_jwt(user["id"], device_id)
    refresh_hash = _hash_token(refresh)

    with db.conn() as c:
        c.execute(
            "INSERT INTO app_refresh_tokens(user_id, token_hash, device_id, expires_at) "
            "VALUES(?,?,?,?)",
            (user["id"], refresh_hash, device_id, now + 7_776_000)
        )

    log.info(
        "device_switch_verify: user_id=%s switched to device %s…",
        user["id"], (device_id[:8] if len(device_id) >= 8 else device_id)
    )

    return jsonify({
        "ok":            True,
        "access_token":  access,
        "refresh_token": refresh,
        "user_id":       user["id"],
        "phone":         phone,
        "user": {
            "id":    user["id"],
            "phone": phone,
            "plan":  _get_plan(user["id"]),
        },
    })


def _send_whatsapp_otp(phone: str, message: str) -> None:
    """Best-effort WhatsApp OTP delivery via the local wa-bot (port 3000).
    Runs in a daemon thread so it never blocks the HTTP response.
    Silently logs failure — the OTP is already stored in settings.
    """
    def _attempt() -> None:
        try:
            # Convert 03001234567 → 923001234567@s.whatsapp.net
            jid = phone.lstrip("0")
            if not jid.startswith("92"):
                jid = "92" + jid
            jid = jid + "@s.whatsapp.net"
            import requests as _req
            resp = _req.post(
                "http://127.0.0.1:3000/api/send-message",
                json={"jid": jid, "text": message},
                timeout=8,
            )
            if resp.status_code == 200:
                log.info("OTP WhatsApp: sent to %s", phone)
            else:
                log.warning("OTP WhatsApp: HTTP %s for %s", resp.status_code, phone)
        except Exception as _e:
            log.warning("OTP WhatsApp: could not reach wa-bot for %s — %s", phone, _e)

    import threading as _thr
    _thr.Thread(target=_attempt, daemon=True, name="otp-wa-send").start()

@bp_auth.route("/me")
@_require_auth
def me(_user_id, _phone):
    if _user_id == 0:
        return jsonify({"ok": True, "id": 0, "phone": "guest",
                        "plan": "free", "subscription": {"is_active": 0}})
    with db.conn() as c:
        user = c.execute(
            "SELECT id, phone, device_name, is_active, created_at, last_login_at, "
            "display_name, email, avatar_color, avatar_emoji "
            "FROM app_users WHERE id=?", (_user_id,)
        ).fetchone()
    if not user:
        return jsonify({"error": "user not found"}), 404
    user = dict(user)
    sub  = _get_subscription_status(_user_id)
    return jsonify({
        "ok":           True,
        "id":           user["id"],
        "phone":        user["phone"],
        "plan":         sub.get("plan", "free"),
        "device_name":  user.get("device_name"),
        "subscription":  sub,
        "is_active":    1 if user.get("is_active", 1) else 0,
        "display_name": user.get("display_name") or "",
        "email":        user.get("email") or "",
        "avatar_color": user.get("avatar_color") or "#8B002D",
        "avatar_emoji": user.get("avatar_emoji") or "",
    })




@bp_auth.route("/profile", methods=["PUT"])
@_require_auth
def update_profile(_user_id, _phone):
    """Update display name, email, and/or avatar for the logged-in user."""
    if _user_id == 0:
        return jsonify({"error": "guests cannot update profile"}), 403
    data = request.get_json(silent=True) or {}
    fields, values = [], []
    if "display_name" in data:
        name = str(data["display_name"]).strip()[:60]
        fields.append("display_name=?"); values.append(name or None)
    if "email" in data:
        email = str(data["email"]).strip()[:120]
        fields.append("email=?"); values.append(email or None)
    if "avatar_color" in data:
        color = str(data["avatar_color"]).strip()[:20]
        fields.append("avatar_color=?"); values.append(color)
    if "avatar_emoji" in data:
        emoji = str(data["avatar_emoji"]).strip()[:10]
        fields.append("avatar_emoji=?"); values.append(emoji)
    if not fields:
        return jsonify({"error": "no fields to update"}), 400
    values.append(_user_id)
    with db.conn() as conn:
        conn.execute(f"UPDATE app_users SET {', '.join(fields)} WHERE id=?", values)
    log.info("profile_updated user_id=%s fields=%s", _user_id, [f.split('=')[0] for f in fields])
    return jsonify({"ok": True})


@bp_auth.route("/change-password", methods=["POST"])
@_require_auth
def change_password(_user_id, _phone):
    """Change the logged-in user's password after verifying the current one."""
    if _user_id == 0:
        return jsonify({"error": "guests do not have a password"}), 403
    data = request.get_json(silent=True) or {}
    current_pw = (data.get("current_password") or "").strip()
    new_pw     = (data.get("new_password")     or "").strip()
    if not current_pw or not new_pw:
        return jsonify({"error": "current_password and new_password required"}), 400
    if len(new_pw) < 6:
        return jsonify({"error": "new password must be at least 6 characters"}), 400
    with db.conn() as conn:
        row = conn.execute("SELECT password_hash FROM app_users WHERE id=?", (_user_id,)).fetchone()
    if not row:
        return jsonify({"error": "user not found"}), 404
    if not _verify_user_password(current_pw, row["password_hash"]):
        return jsonify({"error": "current password is incorrect"}), 401
    new_hash = _hash_user_password(new_pw)
    with db.conn() as conn:
        conn.execute("UPDATE app_users SET password_hash=? WHERE id=?", (new_hash, _user_id))
    log.info("password_changed user_id=%s", _user_id)
    return jsonify({"ok": True})

@bp_auth.route("/device", methods=["POST"])
@_require_auth
def bind_device(_user_id, _phone):
    if _user_id == 0:
        return jsonify({"error": "guests cannot bind a device"}), 403
    data        = request.get_json(silent=True) or {}
    device_id   = (data.get("device_id") or "").strip()
    device_name = (data.get("device_name") or "Android Device").strip()
    if not device_id:
        return jsonify({"error": "device_id required"}), 400
    now = int(time.time())
    with db.conn() as c:
        user = c.execute(
            "SELECT device_id FROM app_users WHERE id=?", (_user_id,)
        ).fetchone()
        if user and user["device_id"] and user["device_id"] != device_id:
            return jsonify({
                "error":   "device_conflict",
                "message": "Another device is already bound to this account.",
            }), 409
        c.execute(
            "UPDATE app_users SET device_id=?, device_name=?, device_bound_at=? WHERE id=?",
            (device_id, device_name, now, _user_id)
        )
    return jsonify({"ok": True, "bound": True})


# ── Subscription API ────────────────────────────────────────────────────────

@bp_sub.route("/plans")
def plans():
    plan_rows = db.list_plans(active_only=True)
    out = []
    for p in plan_rows:
        try:
            features = json.loads(p.get("description") or "[]")
        except Exception:
            features = []
        # Derive Jazz savings message
        gb = p.get("monthly_limit_gb") or 0
        price = p.get("price_pkr") or 0
        jazz_cost = round(gb * 15, 0) if gb else 0  # ~Rs.15/GB on Jazz bundles
        savings_pct = round((1 - price / jazz_cost) * 100) if jazz_cost and price else 0
        savings_msg = (
            f"{savings_pct}% cheaper than Jazz data alone"
            if savings_pct > 0 else ""
        )
        out.append({
            "id":              str(p["id"]),
            "name":            p.get("name", ""),
            "price_monthly":   price,
            "data_gb":         gb,
            "max_devices":     p.get("max_devices") or 1,
            "duration_days":   p.get("duration_days") or 30,
            "features":        features,
            "is_active":       bool(p.get("is_active", 1)),
            "color":           p.get("color") or "#E8002D",
            "jazz_savings_msg": savings_msg,
        })
    # Seed default plans if none exist in DB
    if not out:
        out = [
            {"id": "starter",  "name": "Starter",  "price_monthly": 150,
             "data_gb": 10,  "max_devices": 1, "duration_days": 30,
             "features": ["Zero-data streaming", "HD quality", "All content"],
             "is_active": True, "color": "#E8002D",
             "jazz_savings_msg": "67% cheaper than Jazz data"},
            {"id": "basic",    "name": "Basic",    "price_monthly": 250,
             "data_gb": 30,  "max_devices": 1, "duration_days": 30,
             "features": ["Zero-data streaming", "HD 720p quality", "All content"],
             "is_active": True, "color": "#7C5CFF",
             "jazz_savings_msg": "44% cheaper than Jazz data"},
            {"id": "standard", "name": "Standard", "price_monthly": 400,
             "data_gb": 60,  "max_devices": 1, "duration_days": 30,
             "features": ["Zero-data streaming", "Full HD 1080p", "All content"],
             "is_active": True, "color": "#2563EB",
             "jazz_savings_msg": "56% cheaper than Jazz data"},
            {"id": "premium",  "name": "Premium",  "price_monthly": 700,
             "data_gb": 100, "max_devices": 2, "duration_days": 30,
             "features": ["Zero-data streaming", "Full HD 1080p", "All content", "2 devices"],
             "is_active": True, "color": "#22C55E",
             "jazz_savings_msg": "53% cheaper than Jazz data"},
        ]
    return jsonify({"ok": True, "plans": out})


@bp_sub.route("/status")
@_require_auth
def subscription_status(_user_id, _phone):
    if _user_id == 0:
        return jsonify({"ok": True, "is_active": 0, "plan": "free",
                        "quota": {"allowed": True, "plan_name": "guest",
                                  "is_exceeded": False, "monthly_limit_gb": 0,
                                  "monthly_used_gb": 0, "resets_at": None}})
    sub   = _get_subscription_status(_user_id)
    quota = _compute_app_quota(_user_id)
    return jsonify({"ok": True, **sub, "quota": quota})


@bp_sub.route("/tid/submit", methods=["POST"])
@_require_auth
def tid_submit(_user_id, _phone):
    data           = request.get_json(silent=True) or {}
    phone          = (data.get("phone") or _phone).strip()
    tid            = (data.get("tid") or "").strip()
    plan           = (data.get("plan") or "basic").strip()
    payment_method = (data.get("payment_method") or "jazzcash").strip()
    if not tid:
        return jsonify({"error": "Transaction ID is required"}), 400
    if len(tid) < 5:
        return jsonify({"error": "Enter a valid Transaction ID"}), 400
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO tid_payments"
            "(user_id, phone, amount_pkr, tid, payment_method, plan, submitted_at) "
            "VALUES(?,?,?,?,?,?,?)",
            (_user_id, phone, 0, tid, payment_method, plan, now)
        )
    return jsonify({
        "ok":      True,
        "message": "TID submitted. You'll be notified within 24 hours.",
    })


@bp_sub.route("/tid/status")
@_require_auth
def tid_status(_user_id, _phone):
    with db.conn() as c:
        row = c.execute(
            "SELECT * FROM tid_payments WHERE user_id=? ORDER BY submitted_at DESC LIMIT 1",
            (_user_id,)
        ).fetchone()
    if not row:
        return jsonify({"ok": True, "status": "none", "tid": None})
    row = dict(row)
    return jsonify({
        "ok":           True,
        "status":       row.get("status", "pending"),
        "tid":          row.get("tid"),
        "plan":         row.get("plan"),
        "admin_note":   row.get("admin_note"),
        "submitted_at": row.get("submitted_at"),
        "reviewed_at":  row.get("reviewed_at"),
    })


@bp_sub.route("/tid/check_by_phone", strict_slashes=False)
@_require_auth
def tid_check_by_phone(_user_id, _phone):
    """GET /api/subscription/tid/check_by_phone?phone=<phone>
    Returns all TID payments for the authenticated user as a list.
    Called by Flutter TidStatusScreen to poll payment verification.
    The ?phone param is accepted but ignored — auth token identifies the user.
    Response: {"ok": true, "payments": [{tid, status, plan, admin_note, ...}]}
    """
    with db.conn() as c:
        rows = c.execute(
            "SELECT tid, status, plan, admin_note, submitted_at, reviewed_at "
            "FROM tid_payments WHERE user_id=? ORDER BY submitted_at DESC LIMIT 10",
            (_user_id,)
        ).fetchall()
    return jsonify({"ok": True, "payments": [dict(r) for r in rows]})


# ── Usage API (Phase 6) ─────────────────────────────────────────────────────

def _compute_app_quota(user_id: int) -> dict:
    """Build quota dict for an app user based on their app subscription.
    Replaces db.check_quota() which only knows about JazzDrive accounts.
    """
    user_jid      = f"app_{user_id}"
    sub           = _get_subscription_status(user_id)
    today_bytes   = (db.get_usage_today(user_jid)  or {}).get('bytes_used', 0) or 0
    month_bytes   = (db.get_usage_month(user_jid) or {}).get('bytes_used', 0) or 0
    today_gb      = today_bytes  / (1024 ** 3)
    month_gb      = month_bytes  / (1024 ** 3)

    plan_name     = sub.get("plan_name")   or sub.get("plan", "free").title()
    sub_plan      = sub.get("plan", "free")
    sub_expires   = sub.get("expires_at")

    if not sub.get("is_active"):
        return {
            "allowed":          True,
            "plan_name":        "free",
            "daily_limit_gb":   0,
            "monthly_limit_gb": 0,
            "daily_used_gb":    round(today_gb, 3),
            "monthly_used_gb":  round(month_gb, 3),
            "is_exceeded":      False,
            "resets_at":        None,
            "sub_plan":         "free",
            "sub_expires_at":   None,
        }

    daily_limit   = float(sub.get("daily_limit_gb")   or 0)
    monthly_limit = float(sub.get("monthly_limit_gb") or 0)

    if daily_limit > 0 and today_gb >= daily_limit:
        return {
            "allowed":          False,
            "reason":           "daily_limit_reached",
            "plan_name":        plan_name,
            "daily_limit_gb":   daily_limit,
            "daily_used_gb":    round(today_gb, 3),
            "monthly_limit_gb": monthly_limit,
            "monthly_used_gb":  round(month_gb, 3),
            "is_exceeded":      True,
            "resets_at":        sub_expires,
            "sub_plan":         sub_plan,
            "sub_expires_at":   sub_expires,
        }

    if monthly_limit > 0 and month_gb >= monthly_limit:
        return {
            "allowed":              False,
            "reason":               "monthly_limit_reached",
            "plan_name":            plan_name,
            "monthly_limit_gb":     monthly_limit,
            "monthly_used_gb":      round(month_gb, 3),
            "monthly_remaining_gb": 0.0,
            "is_exceeded":          True,
            "resets_at":            sub_expires,
            "sub_plan":             sub_plan,
            "sub_expires_at":       sub_expires,
        }

    return {
        "allowed":              True,
        "plan_name":            plan_name,
        "daily_limit_gb":       daily_limit,
        "monthly_limit_gb":     monthly_limit,
        "daily_used_gb":        round(today_gb, 3),
        "monthly_used_gb":      round(month_gb, 3),
        "daily_remaining_gb":   round(max(0.0, daily_limit  - today_gb),  3) if daily_limit   else None,
        "monthly_remaining_gb": round(max(0.0, monthly_limit - month_gb), 3) if monthly_limit else None,
        "is_exceeded":          False,
        "resets_at":            sub_expires,
        "sub_plan":             sub_plan,
        "sub_expires_at":       sub_expires,
    }


@bp_usage.route("", methods=["POST"], strict_slashes=False)
@_require_auth
def log_usage_endpoint(_user_id, _phone):
    """Accept bytes_used report from the Flutter app."""
    if _user_id == 0:
        return jsonify({"ok": True, "quota": {"allowed": True}})
    data       = request.get_json(silent=True) or {}
    bytes_used = int(data.get("bytes_used") or data.get("bytes") or 0)
    if bytes_used < 0:
        return jsonify({"error": "bytes_used must be non-negative"}), 400
    user_jid = f"app_{_user_id}"
    db.log_usage(user_jid, bytes_used=bytes_used, requests=1)
    quota = _compute_app_quota(_user_id)
    return jsonify({"ok": True, "quota": quota})


@bp_usage.route("/quota")
@_require_auth
def get_quota(_user_id, _phone):
    if _user_id == 0:
        return jsonify({"ok": True, "quota": {"allowed": True, "plan_name": "guest"}})
    quota    = _compute_app_quota(_user_id)
    user_jid = f"app_{_user_id}"
    return jsonify({
        "ok":    True,
        "quota": quota,
        "today": db.get_usage_today(user_jid)  or 0,
        "month": db.get_usage_month(user_jid) or 0,
    })


# ── Payment methods API ─────────────────────────────────────────────────────

@bp_pay.route("", strict_slashes=False)
def payment_methods():
    """Public — returns enabled payment gateways (no auth required)."""
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT code, name, account_number, instructions, is_enabled "
                "FROM payment_methods WHERE is_enabled=1 ORDER BY sort_order ASC"
            ).fetchall()
        if rows:
            methods = [dict(r) for r in rows]
        else:
            raise Exception("no rows")
    except Exception:
        methods = [
            {"code": "jazzcash",  "name": "JazzCash",
             "account_number": "",
             "instructions":   "Please contact support to get the payment number.",
             "is_enabled": True},
            {"code": "easypaisa", "name": "EasyPaisa",
             "account_number": "",
             "instructions":   "Please contact support to get the payment number.",
             "is_enabled": True},
        ]
    out = [{
        "code":           m.get("code", ""),
        "name":           m.get("name", ""),
        "account_number": m.get("account_number") or "",
        "instructions":   m.get("instructions") or "",
        "enabled":        bool(m.get("is_enabled", True)),
    } for m in methods]
    return jsonify({"ok": True, "methods": out})


# ── Notifications API ───────────────────────────────────────────────────────

@bp_notif.route("/", strict_slashes=False)
@_require_auth
def list_notifications(_user_id, _phone):
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT id, title, body, image_url, action_url, is_read, created_at "
                "FROM notifications WHERE (user_id=? OR user_id IS NULL) "
                "ORDER BY created_at DESC LIMIT 50",
                (_user_id,)
            ).fetchall()
        notifs    = []
        unread    = 0
        for r in rows:
            d = dict(r)
            d["is_read"] = bool(d.get("is_read", 0))
            if not d["is_read"]:
                unread += 1
            notifs.append(d)
        return jsonify({"ok": True, "notifications": notifs, "unread_count": unread})
    except Exception:
        return jsonify({"ok": True, "notifications": [], "unread_count": 0})


@bp_notif.route("/read", methods=["POST"])
@_require_auth
def mark_read(_user_id, _phone):
    data = request.get_json(silent=True) or {}
    ids  = [int(i) for i in (data.get("ids") or []) if str(i).isdigit()]
    try:
        with db.conn() as c:
            if ids:
                ph = ",".join("?" * len(ids))
                c.execute(
                    f"UPDATE notifications SET is_read=1 "
                    f"WHERE id IN ({ph}) AND (user_id=? OR user_id IS NULL)",
                    (*ids, _user_id)
                )
            else:
                c.execute(
                    "UPDATE notifications SET is_read=1 WHERE user_id=? OR user_id IS NULL",
                    (_user_id,)
                )
    except Exception:
        pass
    return jsonify({"ok": True})


@bp_notif.route("/image/<int:notif_id>")
@_require_auth
def notif_image(notif_id, _user_id=None, _phone=None):
    try:
        with db.conn() as c:
            row = c.execute(
                "SELECT image_url FROM notifications WHERE id=?", (notif_id,)
            ).fetchone()
        if row and row["image_url"]:
            from flask import redirect
            return redirect(row["image_url"])
    except Exception:
        pass
    return jsonify({"error": "not found"}), 404


# ── Watch History API ───────────────────────────────────────────────────────

@bp_hist.route("", strict_slashes=False)
@_require_auth
def get_history(_user_id, _phone):
    if _user_id == 0:
        return jsonify({"ok": True, "history": []})
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT file_id, position_ms, duration_ms, watched_at "
                "FROM watch_history WHERE user_id=? ORDER BY watched_at DESC LIMIT 50",
                (_user_id,)
            ).fetchall()
        return jsonify({"ok": True, "history": [dict(r) for r in rows]})
    except Exception:
        return jsonify({"ok": True, "history": []})


@bp_hist.route("/<file_id>", methods=["POST"])
@_require_auth
def save_history(file_id, _user_id, _phone):
    if _user_id == 0:
        return jsonify({"ok": True})
    data        = request.get_json(silent=True) or {}
    position_ms = int(data.get("position_ms") or 0)
    duration_ms = int(data.get("duration_ms") or 0)
    now         = int(time.time())
    try:
        with db.conn() as c:
            c.execute(
                "INSERT INTO watch_history"
                "(user_id, file_id, position_ms, duration_ms, watched_at) "
                "VALUES(?,?,?,?,?) "
                "ON CONFLICT(user_id, file_id) DO UPDATE SET "
                "position_ms=excluded.position_ms, "
                "duration_ms=excluded.duration_ms, "
                "watched_at=excluded.watched_at",
                (_user_id, file_id, position_ms, duration_ms, now)
            )
    except Exception as e:
        log.warning("save_history error: %s", e)
    return jsonify({"ok": True})




# ── App version / update check ─────────────────────────────────────────────

# ── Recommendations ────────────────────────────────────────────────────────
# BUG-A26: radd_recommend.py had no API endpoint — Flutter could never call it.
bp_rec = Blueprint("mobile_rec", __name__)

@bp_rec.route("/recommend", methods=["GET"], strict_slashes=False)
@_require_auth
def get_recommendations(_user_id, _phone):
    """GET /api/recommend
    Returns up to `limit` TMDB-seeded recommended titles not already in
    the user's library.  Cached 12h server-side in recommendation_cache.
    """
    try:
        limit = min(int(request.args.get("limit", 24)), 100)
    except (TypeError, ValueError):
        limit = 24
    try:
        from ..radd_recommend import get_recommendations as _rec
        results = _rec(limit=limit)
        return jsonify({"ok": True, "results": results, "count": len(results)})
    except Exception as e:
        log.warning("recommend error: %s", e)
        return jsonify({"ok": True, "results": [], "count": 0})


bp_app = Blueprint("mobile_app_check", __name__)

@bp_app.route("/version", methods=["GET"])
def app_version():
    """GET /api/app/version — lightweight version probe (no auth).
    Returns current app version string from settings. Used by CI test suite.
    """
    try:
        with db.conn() as c:
            row = c.execute("SELECT v FROM settings WHERE k='app_current_version'").fetchone()
            ver = row["v"] if row and row["v"] else "1.0.0"
    except Exception:
        ver = "1.0.0"
    return jsonify({"ok": True, "version": ver})


@bp_app.route("/check", methods=["POST"])
def app_check():
    """Called by AppUpdateService.check() on every cold start.
    Reads force_update / blocked flags from the settings table.
    Returns {force_update, blocked, message, update_url, current_version}."""
    try:
        data = request.get_json(force=True, silent=True) or {}
        version_code = int(data.get("version_code") or 0)
    except Exception:
        version_code = 0

    try:
        with db.conn() as c:
            def _s(k, default=""):
                row = c.execute("SELECT v FROM settings WHERE k=?", (k,)).fetchone()
                return row["v"] if row and row["v"] is not None else default

            current_version = _s("app_current_version", "1.0.0")
            min_code        = int(_s("app_min_version_code", "0") or 0)
            blocked_code    = int(_s("app_blocked_version_code", "0") or 0)
            update_url      = _s("app_update_url", "")
            blocked_message = _s("app_blocked_message", "")
            update_message  = _s("app_update_message", "")

        force_update = version_code > 0 and min_code > 0 and version_code < min_code
        blocked      = blocked_code > 0 and version_code == blocked_code
        message      = (blocked_message if blocked else update_message)                        if (blocked or force_update) else ""

        return jsonify({
            "ok":              True,
            "force_update":    force_update,
            "blocked":         blocked,
            "message":         message,
            "update_url":      update_url,
            "current_version": current_version,
        })
    except Exception as e:
        log.warning("app_check error: %s", e)
        return jsonify({"ok": True, "force_update": False, "blocked": False,
                        "message": "", "update_url": "", "current_version": ""})


@bp_app.route("/config", methods=["GET"])
def app_config():
    """GET /api/app/config — public, no auth required.
    Called on every cold start by RemoteConfig.fetch().
    Returns all server-controlled config values so the app never needs an
    APK rebuild to change support numbers, CDN URLs, flags, or brand theme.
    """
    def _s(k, default=""):
        try:
            return db.setting(k, default) or default
        except Exception:
            return default

    def _flag(k, default="true"):
        return _s(k, default).lower() in ("1", "true", "yes")

    try:
        support_whatsapp = _s("SUPPORT_WHATSAPP_NUMBER", "923257719165")
        current_version  = _s("app_current_version", "1.0.0")
        min_code         = int(_s("app_min_version_code", "0") or 0)
        update_url       = _s("app_update_url",
                              "https://github.com/raddclub/raddflix-app/releases/latest")
        update_message   = _s("app_update_message", "")

        flags = {
            "otp_device_switch":   _flag("ff_otp_device_switch",   "true"),
            "recommendations":     _flag("ff_recommendations",     "true"),
            "zero_rating":         _flag("ff_zero_rating",         "true"),
            "guest_mode":          _flag("ff_guest_mode",          "true"),
            "maintenance_mode":    _flag("ff_maintenance_mode",    "false"),
            "maintenance_message": _s("ff_maintenance_message", ""),
            "xor_encoding":        _flag("ff_xor_encoding",        "true"),
        }

        _brand_defaults = {
            "brand_primary_color":      "#E8002D",
            "brand_accent_color":       "#FF5C5C",
            "brand_tagline":            "Zero-rated Pakistani streaming",
            "brand_logo_url":           "",
            "brand_splash_color":       "#08080E",
            "brand_background_color":   "#08080E",
            "brand_surface_color":      "#0E0E1C",
            "brand_card_color":         "#1A1A2E",
            "brand_text_primary_color": "#F2F2FF",
            "brand_app_name":           "RaddFlix",
            "brand_font":               "inter",
            "brand_button_radius":      "14",
            "brand_status_bar_dark":    "true",
            "brand_onboarding_pages":   "[]",
        }
        brand = {k: _s(k, v) for k, v in _brand_defaults.items()}

        return jsonify({
            "ok":               True,
            "api_base_url":     db.setting("api_base_url", "") or "http://92.4.95.252",
            "support_whatsapp": support_whatsapp,
            "current_version":  current_version,
            "min_version_code": min_code,
            "update_url":       update_url,
            "update_message":   update_message,
            "flags":            flags,
            "brand":            brand,
        })

    except Exception as _e:
        log.warning("app_config error: %s", _e)
        return jsonify({
            "ok":               True,
            "api_base_url":     db.setting("api_base_url", "") or "http://92.4.95.252",
            "support_whatsapp": "923257719165",
            "current_version":  "1.0.0",
            "min_version_code": 0,
            "update_url":       "",
            "update_message":   "",
            "flags": {
                "otp_device_switch":   True,
                "recommendations":     True,
                "zero_rating":         True,
                "guest_mode":          True,
                "maintenance_mode":    False,
                "maintenance_message": "",
                "xor_encoding":        True,
            },
            "brand": {},
        })

# ── Helpers ────────────────────────────────────────────────────────────────

def _normalize_phone(phone: str) -> str:
    phone = phone.strip().replace(" ", "").replace("-", "")
    if phone.startswith("+92"):
        phone = "0" + phone[3:]
    elif phone.startswith("92") and len(phone) == 12:
        phone = "0" + phone[2:]
    return phone


def _get_plan(user_id: int) -> str:
    now = int(time.time())
    with db.conn() as c:
        row = c.execute(
            "SELECT plan FROM app_subscriptions "
            "WHERE user_id=? AND is_active=1 AND expires_at>? "
            "ORDER BY id DESC LIMIT 1",
            (user_id, now)
        ).fetchone()
    return row["plan"] if row else "free"


def _get_subscription_status(user_id: int) -> dict:
    now = int(time.time())
    with db.conn() as c:
        row = c.execute(
            "SELECT s.plan, s.expires_at, p.name as plan_name, "
            "p.monthly_limit_gb, p.daily_limit_gb "
            "FROM app_subscriptions s "
            "LEFT JOIN plans p ON LOWER(p.name)=LOWER(s.plan) "
            "WHERE s.user_id=? AND s.is_active=1 AND s.expires_at>? "
            "ORDER BY s.id DESC LIMIT 1",
            (user_id, now)
        ).fetchone()
    if not row:
        return {"is_active": 0, "plan": "free", "expires_at": None}
    row = dict(row)
    return {
        "is_active":          1,
        "plan":               row.get("plan", "free"),
        "plan_name":          row.get("plan_name") or row.get("plan", "free").title(),
        "expires_at":         _epoch_to_iso(row.get("expires_at")),
        "monthly_limit_gb":   row.get("monthly_limit_gb"),
        "daily_limit_gb":     row.get("daily_limit_gb"),
    }


def _epoch_to_iso(ts) -> Optional[str]:
    if not ts:
        return None
    try:
        from datetime import datetime, timezone
        return datetime.fromtimestamp(int(ts), tz=timezone.utc).isoformat()
    except Exception:
        return None
