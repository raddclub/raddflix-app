"""Security telemetry — receives tamper-attempt reports from mobile apps.

Endpoint: POST /api/security/tamper-report

No authentication required — a cracked APK may not have a valid JWT.
Rate-limited by IP: max 10 reports per IP per hour (prevents flooding).

Payload (JSON):
  device_hash  — short non-reversible hash of device ID (privacy-safe)
  reason       — 'signature_mismatch' | 'frida_detected' | 'frida_port' | 'root_detected'
  timestamp    — Unix timestamp (seconds)
  app_version  — e.g. '1.0'
  is_rooted    — bool

Admin panel: /security/tamper-reports  (admin login required)
"""
from __future__ import annotations
import logging
import time
import json

from flask import Blueprint, jsonify, request, render_template_string
from .. import db
from ..auth import login_required

log = logging.getLogger("hub.security_telemetry")

bp_security = Blueprint("security_telemetry", __name__)

# ── Rate limiting (in-memory, per-IP, 1h window) ──────────────────────────────
_ip_window: dict[str, list[float]] = {}
_RATE_LIMIT_WINDOW = 3600  # 1 hour
_RATE_LIMIT_MAX    = 10    # max reports per IP per window


def _rate_check(ip: str) -> bool:
    """Return True if the request is allowed, False if rate-limited.

    Also prunes the global _ip_window dict to prevent unbounded memory growth
    under sustained DoS from rotating IPs (P2.2 fix).
    """
    now = time.time()
    hits = _ip_window.get(ip, [])
    hits = [t for t in hits if now - t < _RATE_LIMIT_WINDOW]
    if len(hits) >= _RATE_LIMIT_MAX:
        _ip_window[ip] = hits  # keep for rate-limit enforcement
        return False
    hits.append(now)
    _ip_window[ip] = hits

    # Prune stale IPs every ~100 calls (cheap amortized cleanup)
    if len(_ip_window) > 500:
        stale = [k for k, v in list(_ip_window.items())
                 if not any(now - t < _RATE_LIMIT_WINDOW for t in v)]
        for k in stale:
            del _ip_window[k]

    return True


# ── Mobile endpoint (no auth) ─────────────────────────────────────────────────

@bp_security.route("/api/security/tamper-report", methods=["POST"])
def tamper_report():
    """Receive a tamper-detection event from a mobile app."""
    ip = request.headers.get("X-Forwarded-For", request.remote_addr or "unknown")
    ip = ip.split(",")[0].strip()

    if not _rate_check(ip):
        # Return 200 anyway — don't tell attacker they're being throttled
        return jsonify({"ok": True}), 200

    data = request.get_json(silent=True) or {}

    device_hash = str(data.get("device_hash", ""))[:32]
    reason      = str(data.get("reason", "unknown"))[:64]
    timestamp   = int(data.get("timestamp", int(time.time())))
    app_version = str(data.get("app_version", ""))[:20]
    is_rooted   = bool(data.get("is_rooted", False))

    # Validate reason whitelist
    valid_reasons = {
        "signature_mismatch", "frida_detected", "frida_port",
        "root_detected", "unknown"
    }
    if reason not in valid_reasons:
        reason = "unknown"

    try:
        with db.conn() as c:
            c.execute(
                """INSERT INTO tamper_reports
                   (device_hash, reason, reported_at, app_version, is_rooted, ip_addr)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (device_hash, reason, timestamp, app_version,
                 1 if is_rooted else 0, ip[:64])
            )
        log.warning(
            "TAMPER DETECTED: device=%s reason=%s ip=%s version=%s rooted=%s",
            device_hash, reason, ip, app_version, is_rooted
        )
    except Exception as e:
        log.error("Failed to store tamper report: %s", e)

    # Always return 200 — don't reveal whether logging succeeded
    return jsonify({"ok": True}), 200


# ── Admin panel view ──────────────────────────────────────────────────────────

_PANEL_HTML = """
<!doctype html><html lang="en">
<head>
  <meta charset="utf-8">
  <title>Tamper Reports — RaddHub</title>
  <style>
    body { font-family: monospace; background: #0e0e18; color: #e0e0ff; padding: 24px; }
    h1   { color: #e8002d; }
    table{ border-collapse: collapse; width: 100%; font-size: 13px; }
    th   { background: #1a1a2e; padding: 8px 12px; text-align: left; color: #aaa; }
    td   { padding: 6px 12px; border-bottom: 1px solid #252540; }
    .sig { color: #ef4444; }
    .fri { color: #f59e0b; }
    .roo { color: #8b5cf6; }
    .unk { color: #6b7280; }
    .cnt { font-size: 12px; color: #6b7280; margin-bottom: 16px; }
    tr:hover td { background: #161628; }
    .badge-rooted { background: #8b5cf6; color: #fff; padding: 1px 6px; border-radius: 4px; font-size: 11px; }
  </style>
</head>
<body>
<h1>🔐 Tamper Detection Reports</h1>
<div class="cnt">{{ rows|length }} events (last 500)</div>
<table>
  <tr>
    <th>Time</th><th>Device Hash</th><th>Reason</th>
    <th>App Version</th><th>Rooted</th><th>IP</th>
  </tr>
  {% for r in rows %}
  <tr>
    <td>{{ r.reported_at | datetimeformat }}</td>
    <td>{{ r.device_hash }}</td>
    <td class="{{ r.reason[:3] }}">{{ r.reason }}</td>
    <td>{{ r.app_version }}</td>
    <td>{% if r.is_rooted %}<span class="badge-rooted">YES</span>{% else %}—{% endif %}</td>
    <td>{{ r.ip_addr }}</td>
  </tr>
  {% endfor %}
</table>
{% if not rows %}<p style="color:#6b7280">No tamper events yet. 🎉</p>{% endif %}
</body></html>
"""


@bp_security.route("/security/tamper-reports")
@login_required
def tamper_reports_panel():
    """Admin panel: view all tamper detection events."""
    try:
        with db.conn() as c:
            rows = c.execute(
                """SELECT * FROM tamper_reports
                   ORDER BY reported_at DESC LIMIT 500"""
            ).fetchall()
    except Exception:
        rows = []

    import datetime

    def _fmt(ts):
        try:
            return datetime.datetime.utcfromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
        except Exception:
            return str(ts)

    row_dicts = [dict(r) for r in rows]

    from jinja2 import Environment
    env = Environment()
    env.filters["datetimeformat"] = _fmt
    tmpl = env.from_string(_PANEL_HTML)
    return tmpl.render(rows=row_dicts)
