"""Server-side XOR encoding layer — mirrors Flutter's RequestEncoder.

This module is the Python counterpart to:
  raddflix_flutter/lib/core/security/request_encoder.dart

Activation:
  1. Deploy this module (already done when radd-hub is updated)
  2. Set RequestEncoder.enabled = true in Flutter (app update or RemoteConfig)
  3. Both sides MUST be deployed simultaneously — partial state breaks all API calls

Session key derivation (must match Flutter exactly):
  key = SHA-256("raddflix_xor_v1" + ":" + deviceId + ":" + day + ":" + hour)[:32]
  day  = UTC day-of-month (1–31)
  hour = UTC hour (0–23)
  Key rotates every hour.

Wire into Flask routes:
  from .request_encoding import decode_request, encode_response, is_encoded_request
  # In any route that needs encoding support:
  body = decode_request(request) if is_encoded_request(request) else request.json
  return encode_response(result, session_key) if is_encoded_request(request) else jsonify(result)

Or use the blueprint decorator @encoding_supported for automatic decode/encode.
"""
from __future__ import annotations
import base64
import hashlib
import json
import logging
from datetime import datetime, timezone
from functools import wraps
from typing import Optional

from flask import Blueprint, request, jsonify, Response, g

log = logging.getLogger("hub.request_encoding")

# Must match Flutter's RequestEncoder._xorSeed constant
_XOR_SEED = "raddflix_xor_v1"

# Header names used by the Flutter app
HEADER_ENCODED   = "X-Encoded"     # Value "1" → request body is XOR-encoded
HEADER_DEVICE_ID = "X-Device-Id"  # Device ID used to derive session key


# ── Key Derivation ─────────────────────────────────────────────────────────────

def generate_session_key(device_id: str, hour_offset: int = 0) -> str:
    """Derive the hourly session key for a device.

    Must produce the same output as Flutter's RequestEncoder.generateSessionKey().
    Key formula: SHA-256("raddflix_xor_v1:deviceId:day:hour")[:32]

    Args:
        device_id:   Android device ID (from app registration / JWT)
        hour_offset: 0 = current hour, -1 = previous hour (handles clock-edge requests)
    """
    now = datetime.now(timezone.utc)
    # Simulate hour_offset by subtracting seconds
    if hour_offset != 0:
        from datetime import timedelta
        now = now + timedelta(hours=hour_offset)
    raw = f"{_XOR_SEED}:{device_id}:{now.day}:{now.hour}"
    return hashlib.sha256(raw.encode()).hexdigest()[:32]


def _candidate_keys(device_id: str) -> list[str]:
    """Return [current_key, previous_key] to handle clock-edge requests."""
    return [
        generate_session_key(device_id, 0),
        generate_session_key(device_id, -1),
    ]


# ── XOR Encode / Decode ────────────────────────────────────────────────────────

def xor_encode(data: bytes, key: str) -> str:
    """XOR-encode bytes with key, return URL-safe base64 (no padding).

    Matches Flutter: base64Url.encode(encoded) — URL-safe, no padding.
    """
    key_bytes = key.encode("utf-8")
    encoded = bytes(
        data[i] ^ key_bytes[i % len(key_bytes)] for i in range(len(data))
    )
    return base64.urlsafe_b64encode(encoded).rstrip(b"=").decode()


def xor_decode(encoded: str, key: str) -> bytes:
    """XOR-decode a URL-safe base64 string with key.

    Matches Flutter: base64Url.decode(encoded), then XOR.
    """
    # Re-add base64 padding stripped by Flutter
    padded = encoded + "=" * ((4 - len(encoded) % 4) % 4)
    encoded_bytes = base64.urlsafe_b64decode(padded)
    key_bytes = key.encode("utf-8")
    return bytes(
        encoded_bytes[i] ^ key_bytes[i % len(key_bytes)]
        for i in range(len(encoded_bytes))
    )


# ── Flask Request / Response Helpers ──────────────────────────────────────────

def is_encoded_request(req=None) -> bool:
    """Return True if the client signals it's sending XOR-encoded data."""
    req = req or request
    return req.headers.get(HEADER_ENCODED, "0") == "1"


def get_request_device_id(req=None) -> Optional[str]:
    """Extract device_id from request — tries header first, then JWT payload."""
    req = req or request
    # Prefer explicit header
    device_id = req.headers.get(HEADER_DEVICE_ID, "").strip()
    if device_id:
        return device_id
    # Fall back: extract from JWT 'device_id' claim if present
    try:
        from . import mobile_api
        payload = mobile_api._verify_jwt(req.headers.get("Authorization", "").removeprefix("Bearer "))
        device_id = payload.get("device_id") or payload.get("did") or ""
        if device_id:
            return device_id
    except Exception:
        pass
    return None


def decode_request(req=None) -> Optional[dict]:
    """Decode an XOR-encoded request body.

    Tries current hour key and previous hour key (handles clock-edge requests).
    Returns parsed JSON dict, or None if decoding fails.
    """
    req = req or request
    device_id = get_request_device_id(req)
    if not device_id:
        log.warning("XOR decode: no device_id in request, cannot derive key")
        return None

    raw_body = req.get_data(as_text=True).strip()
    if not raw_body:
        return {}

    for key in _candidate_keys(device_id):
        try:
            decoded_bytes = xor_decode(raw_body, key)
            result = json.loads(decoded_bytes.decode("utf-8"))
            log.debug("XOR decode: success for device=%s...", device_id[:8])
            return result
        except Exception:
            continue

    log.warning("XOR decode: failed for device=%s...", device_id[:8] if device_id else "?")
    return None


def encode_response(data: dict, device_id: str) -> Response:
    """XOR-encode a JSON response for a device.

    Uses current hour key. Client decodes with the same key.
    Falls back to plain JSON if encoding fails.
    """
    if not device_id:
        return jsonify(data)
    try:
        json_bytes = json.dumps(data, separators=(",", ":")).encode("utf-8")
        key = generate_session_key(device_id)
        encoded = xor_encode(json_bytes, key)
        return Response(encoded, content_type="application/octet-stream")
    except Exception as e:
        log.error("XOR encode response failed: %s — falling back to plain JSON", e)
        return jsonify(data)


# ── Flask Decorator ────────────────────────────────────────────────────────────

def encoding_supported(fn):
    """Decorator: auto-decode XOR request body, auto-encode XOR response.

    Wraps a route function so it receives a decoded dict from
    g.decoded_body (if client is using encoding) alongside the normal request.
    The return value (dict) is automatically XOR-encoded if the client requested it.

    Usage:
        @bp.route("/api/some-endpoint", methods=["POST"])
        @encoding_supported
        def some_endpoint():
            data = g.decoded_body or request.json  # works for both old and new clients
            ...
            return {"result": "ok"}  # will be XOR-encoded if client sent X-Encoded: 1
    """
    @wraps(fn)
    def wrapper(*args, **kwargs):
        device_id = get_request_device_id()
        if is_encoded_request() and device_id:
            g.decoded_body = decode_request()
            g.xor_device_id = device_id
        else:
            g.decoded_body = None
            g.xor_device_id = None

        result = fn(*args, **kwargs)

        # Auto-encode response if client requested it
        if g.get("xor_device_id") and isinstance(result, dict):
            return encode_response(result, g.xor_device_id)
        return result if not isinstance(result, dict) else jsonify(result)

    return wrapper


# ── Admin Blueprint ────────────────────────────────────────────────────────────

bp_encoding_admin = Blueprint("encoding_admin", __name__)


@bp_encoding_admin.route("/security/xor-encoding")
def xor_encoding_status():
    """Admin info page: XOR encoding layer status and test tool."""
    from flask import render_template_string, redirect, url_for, request as flask_req
    from ..auth import is_logged_in
    if not is_logged_in():
        return redirect(url_for("auth.login", next=flask_req.path))
    html = """
    <!doctype html><html lang="en">
    <head><meta charset="utf-8"><title>XOR Encoding — RaddHub</title>
    <style>
      body { font-family: monospace; background: #0e0e18; color: #e0e0ff; padding: 24px; }
      h1 { color: #e8002d; }
      .status { background: #1a1a2e; border: 1px solid #252540; padding: 16px; border-radius: 8px; margin: 16px 0; }
      .ok  { color: #22c55e; } .warn { color: #f59e0b; } .err { color: #ef4444; }
      code { background: #0d0d1a; padding: 2px 6px; border-radius: 4px; }
      pre  { background: #0d0d1a; padding: 16px; border-radius: 8px; overflow-x: auto; }
    </style></head>
    <body>
    <h1>🔐 XOR Encoding Layer (Layer 5)</h1>
    <div class="status">
      <p>Status: <span class="warn">⏸ Ready but not active</span></p>
      <p>The server-side encoding module is deployed and ready.</p>
      <p>To activate: set <code>RequestEncoder.enabled = true</code> in Flutter
         (via RemoteConfig or a new APK build) and deploy simultaneously.</p>
    </div>
    <h2>Key Formula</h2>
    <pre>SHA-256("raddflix_xor_v1" + ":" + deviceId + ":" + UTC_day + ":" + UTC_hour)[:32]</pre>
    <h2>Headers</h2>
    <pre>X-Encoded: 1        (client → server: body is XOR+base64url encoded)
X-Device-Id: &lt;id&gt;   (client → server: device ID for key derivation)</pre>
    <h2>Integration</h2>
    <pre>from .request_encoding import encoding_supported, decode_request, encode_response, is_encoded_request

# Option A: decorator (auto decode + encode)
@bp.route("/api/endpoint", methods=["POST"])
@encoding_supported
def endpoint():
    data = g.decoded_body or request.json

# Option B: manual
body = decode_request() if is_encoded_request() else request.json
return encode_response(result, device_id) if is_encoded_request() else jsonify(result)</pre>
    </body></html>
    """
    return render_template_string(html)
