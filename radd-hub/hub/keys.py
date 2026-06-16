"""Multi-key vault with auto-rotation.

Stores any number of keys per provider, encrypted at rest using a key
derived from FLASK_SECRET_KEY. Caller code asks for a "next active key"
and the vault picks the least-recently-used non-exhausted one.
"""
from __future__ import annotations
import os
import time
import json
import base64
import hashlib
import threading
from typing import Optional, List
from . import db, config

try:
    from cryptography.fernet import Fernet, InvalidToken
    _CRYPTO = True
except Exception:
    _CRYPTO = False

PROVIDERS = (
    "tmdb", "groq", "gemini", "openai", "openrouter",
    "github", "gsheets_sa_json",
    "telegram", "whatsapp_admin",
    "omdb",
)

_lock = threading.RLock()


# --------------------------------------------------------------------------- #
# Crypto                                                                      #
# --------------------------------------------------------------------------- #

def _fernet() -> Optional["Fernet"]:
    if not _CRYPTO:
        return None
    secret = os.environ.get("FLASK_SECRET_KEY", "")
    if not secret:
        return None
    raw = hashlib.sha256(secret.encode("utf-8")).digest()
    key = base64.urlsafe_b64encode(raw)
    return Fernet(key)


def encrypt(plain: str) -> bytes:
    f = _fernet()
    if f is None:
        return plain.encode("utf-8")
    return f.encrypt(plain.encode("utf-8"))


def decrypt(blob: bytes) -> str:
    f = _fernet()
    if f is None:
        return blob.decode("utf-8", errors="replace") if isinstance(blob, (bytes, bytearray)) else str(blob)
    if isinstance(blob, str):
        blob = blob.encode("utf-8")
    try:
        return f.decrypt(blob).decode("utf-8")
    except InvalidToken:
        # Probably stored before crypto was enabled
        return blob.decode("utf-8", errors="replace")


# --------------------------------------------------------------------------- #
# CRUD                                                                        #
# --------------------------------------------------------------------------- #

def add_key(provider: str, value: str, label: str = "") -> int:
    if provider not in PROVIDERS:
        raise ValueError(f"unknown provider: {provider}")
    if not value:
        raise ValueError("value required")
    enc = encrypt(value)
    now = int(time.time())
    with _lock, db.conn() as c:
        cur = c.execute("INSERT INTO keys(provider,label,value_enc,is_active,created_at,updated_at) "
                        "VALUES(?,?,?,1,?,?)", (provider, label, enc, now, now))
        return cur.lastrowid


def remove_key(key_id: int) -> None:
    with _lock, db.conn() as c:
        c.execute("DELETE FROM keys WHERE id=?", (key_id,))


def set_active(key_id: int, active: bool) -> None:
    with _lock, db.conn() as c:
        c.execute("UPDATE keys SET is_active=?, updated_at=? WHERE id=?",
                  (1 if active else 0, int(time.time()), key_id))


def list_keys(provider: Optional[str] = None, *, mask: bool = True) -> List[dict]:
    sql = "SELECT * FROM keys"
    args = []
    if provider:
        sql += " WHERE provider=?"
        args.append(provider)
    sql += " ORDER BY provider, id"
    with db.conn() as c:
        rows = [dict(r) for r in c.execute(sql, args).fetchall()]
    out = []
    now = int(time.time())
    for r in rows:
        try:
            v = decrypt(r["value_enc"])
        except Exception:
            v = ""
        masked = _mask(v) if mask else v
        out.append({
            "id": r["id"], "provider": r["provider"], "label": r["label"] or "",
            "value": masked, "value_set": bool(v),
            "is_active": bool(r["is_active"]),
            "exhausted": (r["exhausted_until"] or 0) > now,
            "exhausted_until": r["exhausted_until"],
            "failure_count": r["failure_count"],
            "total_uses": r["total_uses"],
            "last_used_at": r["last_used_at"],
            "last_status": r["last_status"],
        })
    return out


def _mask(v: str) -> str:
    if not v:
        return ""
    if len(v) <= 8:
        return "•" * len(v)
    return v[:4] + "•" * (len(v) - 8) + v[-4:]


# --------------------------------------------------------------------------- #
# Active selection (rotation)                                                 #
# --------------------------------------------------------------------------- #

def get_active_value(provider: str) -> Optional[str]:
    """Return the next usable key value for provider, or None if none.

    Selection: active=1 AND exhausted_until <= now, ordered by least-recently-used.
    Bumps total_uses + last_used_at.
    """
    now = int(time.time())
    with _lock, db.conn() as c:
        r = c.execute("SELECT * FROM keys WHERE provider=? AND is_active=1 "
                      "AND COALESCE(exhausted_until,0) <= ? "
                      "ORDER BY COALESCE(last_used_at,0) ASC LIMIT 1",
                      (provider, now)).fetchone()
        if not r:
            # fallback to env (legacy)
            return _from_env(provider)
        c.execute("UPDATE keys SET total_uses=total_uses+1, last_used_at=? WHERE id=?",
                  (now, r["id"]))
        try:
            return decrypt(r["value_enc"])
        except Exception:
            return None


def get_all_active_values(provider: str) -> List[str]:
    now = int(time.time())
    with db.conn() as c:
        rows = c.execute("SELECT value_enc FROM keys WHERE provider=? AND is_active=1 "
                         "AND COALESCE(exhausted_until,0) <= ?", (provider, now)).fetchall()
    out = []
    for r in rows:
        try:
            out.append(decrypt(r["value_enc"]))
        except Exception:
            pass
    env = _from_env(provider)
    if env and env not in out:
        out.append(env)
    return out


def mark_exhausted(provider: str, value: str, *, retry_after_s: int = 3600) -> None:
    """Temporarily disable a key (rate-limited / quota)."""
    now = int(time.time())
    with _lock, db.conn() as c:
        rows = c.execute("SELECT id, value_enc FROM keys WHERE provider=?", (provider,)).fetchall()
        for r in rows:
            try:
                if decrypt(r["value_enc"]) == value:
                    c.execute("UPDATE keys SET exhausted_until=?, last_status=?, "
                              "failure_count=failure_count+1 WHERE id=?",
                              (now + retry_after_s, "exhausted", r["id"]))
                    break
            except Exception:
                pass


def mark_invalid(provider: str, value: str) -> None:
    """Permanently disable a key (401/403)."""
    with _lock, db.conn() as c:
        rows = c.execute("SELECT id, value_enc FROM keys WHERE provider=?", (provider,)).fetchall()
        for r in rows:
            try:
                if decrypt(r["value_enc"]) == value:
                    c.execute("UPDATE keys SET is_active=0, last_status='invalid', "
                              "failure_count=failure_count+1 WHERE id=?", (r["id"],))
                    break
            except Exception:
                pass


def mark_ok(provider: str, value: str) -> None:
    with _lock, db.conn() as c:
        rows = c.execute("SELECT id, value_enc FROM keys WHERE provider=?", (provider,)).fetchall()
        for r in rows:
            try:
                if decrypt(r["value_enc"]) == value:
                    c.execute("UPDATE keys SET last_status='ok', failure_count=0 WHERE id=?", (r["id"],))
                    break
            except Exception:
                pass


# --------------------------------------------------------------------------- #
# Env compatibility                                                           #
# --------------------------------------------------------------------------- #

_ENV_MAP = {
    "tmdb":    ["TMDB_API_KEY"],
    "groq":    ["GROQ_API_KEY"],
    "gemini":  ["GEMINI_API_KEY"],
    "openai":  ["OPENAI_API_KEY"],
    "openrouter": ["OPENROUTER_API_KEY"],
    "github":  ["GITHUB_TOKEN"],
    "telegram":["TELEGRAM_BOT_TOKEN"],
    "omdb":    ["OMDB_API_KEY"],
}

def _from_env(provider: str) -> Optional[str]:
    for v in _ENV_MAP.get(provider, []):
        x = os.environ.get(v)
        if x:
            return x
    return None


def export_env_compat() -> None:
    """Push current vault values into os.environ so legacy modules see them."""
    for p, names in _ENV_MAP.items():
        v = get_active_value(p)
        if v:
            for name in names:
                os.environ[name] = v


# --------------------------------------------------------------------------- #
# Provider tests                                                              #
# --------------------------------------------------------------------------- #

def test_provider(provider: str, value: str) -> dict:
    """Live-call a provider with the given key. Returns {ok, message}."""
    import requests
    p = provider.lower()
    try:
        if p == "tmdb":
            r = requests.get("https://api.themoviedb.org/3/configuration",
                             params={"api_key": value}, timeout=8)
            return {"ok": r.status_code == 200, "message": f"HTTP {r.status_code}"}
        if p == "groq":
            r = requests.post("https://api.groq.com/openai/v1/chat/completions",
                              headers={"Authorization": f"Bearer {value}",
                                       "Content-Type": "application/json"},
                              json={"model": "llama-3.1-8b-instant",
                                    "messages": [{"role": "user", "content": "hi"}],
                                    "max_tokens": 1},
                              timeout=10)
            return {"ok": r.status_code in (200, 201), "message": f"HTTP {r.status_code}"}
        if p == "gemini":
            r = requests.get(
                f"https://generativelanguage.googleapis.com/v1beta/models?key={value}",
                timeout=10)
            return {"ok": r.status_code == 200, "message": f"HTTP {r.status_code}"}
        if p == "openai":
            r = requests.get("https://api.openai.com/v1/models",
                             headers={"Authorization": f"Bearer {value}"}, timeout=10)
            return {"ok": r.status_code == 200, "message": f"HTTP {r.status_code}"}
        if p == "github":
            r = requests.get("https://api.github.com/user",
                             headers={"Authorization": f"token {value}",
                                      "Accept": "application/vnd.github+json"},
                             timeout=10)
            return {"ok": r.status_code == 200, "message": f"HTTP {r.status_code}"}
        if p == "telegram":
            r = requests.get(f"https://api.telegram.org/bot{value}/getMe", timeout=10)
            return {"ok": r.status_code == 200 and r.json().get("ok") is True,
                    "message": f"HTTP {r.status_code}"}
        if p == "omdb":
            r = requests.get("http://www.omdbapi.com/",
                             params={"apikey": value, "t": "Inception", "type": "movie"},
                             timeout=10)
            if r.status_code == 200:
                data = r.json()
                if data.get("Response") == "True":
                    return {"ok": True, "message": f"OK — {data.get('Title', 'response valid')}"}
                return {"ok": False, "message": data.get("Error", "Response=False")}
            return {"ok": False, "message": f"HTTP {r.status_code}"}
        if p == "gsheets_sa_json":
            try:
                json.loads(value)
                return {"ok": True, "message": "Valid JSON"}
            except Exception as e:
                return {"ok": False, "message": f"Invalid JSON: {e}"}
        return {"ok": False, "message": f"no live test for provider '{p}'"}
    except requests.RequestException as e:
        return {"ok": False, "message": f"request failed: {e}"}
