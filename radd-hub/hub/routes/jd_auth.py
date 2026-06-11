"""JazzDrive auth proxy endpoints for the RaddFlix Flutter app.

POST /api/jd/oauth2/token           — exchange OAuth2 auth code for tokens
POST /api/jd/mobileconnect/validate — MobileConnect (Jazz SIM zero-rated login)
GET  /api/jd/oauth2/authorize_url   — returns the full authorize URL for WebView

Mirrors the exact flows from the JazzDrive Android APK (fnbroot/f&rW23).
All outbound calls include the 4 OkHttp interceptor headers (x-request-id,
User-Agent: omh android client, X-deviceid: fac-*, X-devicename).
"""
from __future__ import annotations
import logging
import time
import uuid

import requests
import urllib3
from flask import Blueprint, jsonify, request

from .. import db
from .. import jazzdrive as jd

log = logging.getLogger("hub.jd_auth")

bp = Blueprint("jd_auth", __name__)

OAUTH_BASE   = "https://jazzdrive.com.pk"
CLOUD_BASE   = "https://cloud.jazzdrive.com.pk"
CLIENT_ID    = "fnbroot"
CLIENT_SECRET = "f&rW23"
REDIRECT_URI = "https://cloud.jazzdrive.com.pk/ui/html/clientoauth.html"


def _build_req_headers(raw_accesstoken: str = "") -> dict:
    """Build the 4 OkHttp interceptor headers for every outbound JazzDrive request."""
    return jd.get_auth_headers(
        vk="",
        jid="",
        msisdn=db.setting("JAZZDRIVE_MSISDN") or "",
        raw_accesstoken=raw_accesstoken or None,
    )


def _clean_proxies(proxies: dict | None) -> dict | None:
    if not proxies:
        return None
    return {k: v for k, v in proxies.items() if k in ("http", "https")}


# ── GET /api/jd/oauth2/authorize_url ─────────────────────────────────────────
@bp.route("/api/jd/oauth2/authorize_url", methods=["GET"])
def jd_oauth2_authorize_url():
    """Return the OAuth2 authorization URL for the Flutter WebView.

    Flutter opens this URL in a WebView, intercepts the redirect to
    REDIRECT_URI, extracts the ?code= parameter, and calls /api/jd/oauth2/token.
    """
    import random
    state = str(random.randint(0, 100000))
    url = (
        f"{OAUTH_BASE}/oauth2/authorization.php"
        f"?response_type=code"
        f"&client_id={CLIENT_ID}"
        f"&redirect_uri={REDIRECT_URI}"
        f"&access_type=offline"
        f"&scope="
        f"&state={state}"
    )
    return jsonify({"ok": True, "authorize_url": url, "state": state, "redirect_uri": REDIRECT_URI})


# ── POST /api/jd/oauth2/token ─────────────────────────────────────────────────
@bp.route("/api/jd/oauth2/token", methods=["POST"])
def jd_oauth2_token():
    """Exchange an OAuth2 authorization code for JazzDrive tokens.

    Body: {"code": "<auth_code>"}
    Returns: {"ok": true, "access_token": "...", "refresh_token": "...", "expires_in": N}

    Flutter calls this after the OAuth2 WebView intercepts the redirect_uri.
    Credentials (fnbroot / f&rW23) are in the POST body per oauth2_authentication_in_body=true.
    """
    data = request.get_json(silent=True) or {}
    code = (data.get("code") or "").strip()
    if not code:
        return jsonify({"error": "code required"}), 400

    try:
        jd.require_wg0()
    except jd.JDVPNRequired as e:
        return jsonify({"error": f"VPN required: {e}"}), 503

    proxies = _clean_proxies(jd.resolve_proxies(purpose="otp"))
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

    try:
        resp = requests.post(
            f"{OAUTH_BASE}/oauth2/token.php",
            data={
                "grant_type":    "authorization_code",
                "code":          code,
                "redirect_uri":  REDIRECT_URI,
                "client_id":     CLIENT_ID,
                "client_secret": CLIENT_SECRET,
            },
            headers={
                **_build_req_headers(),
                "Content-Type": "application/x-www-form-urlencoded",
            },
            timeout=20,
            proxies=proxies,
            verify=False,
        )
    except Exception as e:
        log.error("jd_oauth2_token: network error: %s", e)
        return jsonify({"error": f"Network error: {e}"}), 502

    if resp.status_code != 200:
        log.warning("jd_oauth2_token: HTTP %d — %s", resp.status_code, resp.text[:200])
        return jsonify({
            "error": f"JazzDrive returned HTTP {resp.status_code}",
            "detail": resp.text[:200]
        }), 502

    try:
        body = resp.json()
    except Exception:
        return jsonify({"error": "Non-JSON response from JazzDrive", "detail": resp.text[:200]}), 502

    if body.get("error"):
        return jsonify({"error": body["error"], "detail": body.get("error_description", "")}), 400

    log.info("jd_oauth2_token: code exchanged successfully")
    return jsonify({
        "ok":            True,
        "access_token":  body.get("access_token", ""),
        "refresh_token": body.get("refresh_token", ""),
        "expires_in":    body.get("expires_in", 3600),
        "token_type":    body.get("token_type", "oauth"),
    })


# ── POST /api/jd/mobileconnect/validate ──────────────────────────────────────
@bp.route("/api/jd/mobileconnect/validate", methods=["POST"])
def jd_mobileconnect_validate():
    """Validate a MobileConnect code (Jazz SIM zero-rated login).

    Body: {"code": "<mc_code>", "state": "<mc_state>"}
    Returns: {"ok": true, "access_token": "...", "refresh_token": "...", "msisdn": "..."}

    Flutter calls this after the MobileConnect WebView (mobileconnect.html?embedded=true)
    returns a code+state via JS callback. Jazz network injects the MSISDN header
    at the cell level — no password needed for zero-rated SIM users.
    """
    data  = request.get_json(silent=True) or {}
    code  = (data.get("code")  or "").strip()
    state = (data.get("state") or "").strip()
    if not code:
        return jsonify({"error": "code required"}), 400

    try:
        jd.require_wg0()
    except jd.JDVPNRequired as e:
        return jsonify({"error": f"VPN required: {e}"}), 503

    # cloud.jazzdrive.com.pk is NOT geo-restricted — wg0 routes it directly
    proxies = _clean_proxies(jd.resolve_proxies(purpose="sapi"))

    body_payload = {"data": {"code": code}}
    if state:
        body_payload["data"]["state"] = state

    try:
        resp = requests.post(
            f"{CLOUD_BASE}/sapi/credential/mobileconnect?action=validate&responsetime=true",
            json=body_payload,
            headers=_build_req_headers(),
            timeout=25,
            proxies=proxies,
        )
    except Exception as e:
        log.error("jd_mobileconnect_validate: network error: %s", e)
        return jsonify({"error": f"Network error: {e}"}), 502

    if resp.status_code != 200:
        log.warning("jd_mobileconnect_validate: HTTP %d — %s", resp.status_code, resp.text[:200])
        return jsonify({
            "error": f"JazzDrive returned HTTP {resp.status_code}",
            "detail": resp.text[:200]
        }), 502

    try:
        body = resp.json()
    except Exception:
        return jsonify({"error": "Non-JSON response from JazzDrive", "detail": resp.text[:200]}), 502

    err = body.get("error")
    if err:
        err_code = err.get("code") if isinstance(err, dict) else str(err)
        err_msg  = err.get("message", "") if isinstance(err, dict) else ""
        log.warning("jd_mobileconnect_validate: JD error %s — %s", err_code, err_msg)
        return jsonify({"error": err_code, "detail": err_msg}), 400

    d = body.get("data", body)
    access_token  = d.get("access_token", "")
    refresh_token = d.get("refresh_token", "")
    msisdn        = d.get("msisdn", "")

    if not access_token:
        log.warning("jd_mobileconnect_validate: no access_token in response: %s", body)
        return jsonify({"error": "No access_token in JazzDrive response", "raw": body}), 502

    log.info("jd_mobileconnect_validate: MobileConnect login ok (msisdn=%s...)", msisdn[:5] if msisdn else "?")
    return jsonify({
        "ok":            True,
        "access_token":  access_token,
        "refresh_token": refresh_token,
        "msisdn":        msisdn,
        "expires_in":    d.get("expires_in", 3600),
        "lastrefreshdate": d.get("lastrefreshdate"),
    })
