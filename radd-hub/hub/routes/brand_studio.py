"""Brand Studio blueprint — P6
Admin panel section at /brand/ for full app branding control and APK builds.
Routes:
  GET  /brand/                        — admin UI
  GET  /brand/assets/<filename>       — serve uploaded brand assets
  GET  /api/brand/config              — read brand config
  POST /api/brand/config              — write brand config
  POST /api/brand/save                — persist all fields
  POST /api/brand/upload-image        — upload logo / icon / splash
  GET  /api/brand/build-status        — poll GitHub Actions run status
  POST /api/brand/trigger-build       — dispatch build-apk.yml
"""
from __future__ import annotations
import json
import os
import mimetypes
from pathlib import Path
from flask import Blueprint, jsonify, request, render_template, send_file, abort
from .. import db, auth, config

bp = Blueprint("brand_studio", __name__)

# ── Storage ──────────────────────────────────────────────────────────────────
_BRAND_ASSETS_DIR = config.DATA_DIR / "brand_assets"
_GITHUB_REPO = "raddclub/raddflix-app"
_GITHUB_API  = "https://api.github.com"

BRAND_KEYS = [
    "brand_primary_color",
    "brand_tagline",
    "brand_logo_url",
    "brand_splash_color",
    "brand_onboarding_pages",
    "brand_icon_filename",
    "brand_splash_filename",
]


def _ensure_dir():
    _BRAND_ASSETS_DIR.mkdir(parents=True, exist_ok=True)


def _get_brand_config() -> dict:
    cfg: dict[str, str] = {}
    with db.conn() as c:
        for k in BRAND_KEYS:
            row = c.execute("SELECT v FROM settings WHERE k=?", (k,)).fetchone()
            cfg[k] = row["v"] if row else ""
    cfg.setdefault("brand_primary_color", "#E8002D")
    cfg.setdefault("brand_splash_color",  "#0a0c11")
    cfg.setdefault("brand_tagline",       "Zero-rated Pakistani streaming")
    cfg.setdefault("brand_onboarding_pages", "[]")
    return cfg


def _save_setting(k: str, v: str):
    with db.conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO settings(k,v) VALUES(?,?)", (k, v)
        )


# ── Admin UI ─────────────────────────────────────────────────────────────────

@bp.route("/brand/")
@auth.login_required
def brand_index():
    cfg = _get_brand_config()
    return render_template("brand_studio.html", active="brand", cfg=cfg)


@bp.route("/brand/assets/<filename>")
def brand_asset(filename: str):
    _ensure_dir()
    p = _BRAND_ASSETS_DIR / Path(filename).name
    if not p.exists() or not p.is_file():
        abort(404)
    mime, _ = mimetypes.guess_type(str(p))
    return send_file(str(p), mimetype=mime or "application/octet-stream")


# ── Brand Config API ─────────────────────────────────────────────────────────

@bp.route("/api/brand/config", methods=["GET"])
@auth.login_required
def brand_config_get():
    return jsonify({"ok": True, "config": _get_brand_config()})


@bp.route("/api/brand/config", methods=["POST"])
@auth.login_required
def brand_config_post():
    data = request.get_json(force=True, silent=True) or {}
    for k in BRAND_KEYS:
        if k in data:
            _save_setting(k, str(data[k]))
    return jsonify({"ok": True})


@bp.route("/api/brand/save", methods=["POST"])
@auth.login_required
def brand_save():
    data = request.get_json(force=True, silent=True) or {}
    saved = []
    for k in BRAND_KEYS:
        if k in data:
            _save_setting(k, str(data[k]))
            saved.append(k)
    return jsonify({"ok": True, "saved": saved})


@bp.route("/api/brand/upload-image", methods=["POST"])
@auth.login_required
def brand_upload_image():
    _ensure_dir()
    f = request.files.get("file")
    field = request.form.get("field", "brand_logo")
    if not f or not f.filename:
        return jsonify({"ok": False, "error": "No file"}), 400
    ext = Path(f.filename).suffix.lower()
    if ext not in (".png", ".jpg", ".jpeg", ".webp", ".svg"):
        return jsonify({"ok": False, "error": "Only PNG/JPG/WEBP/SVG allowed"}), 400
    filename = f"{field}{ext}"
    dest = _BRAND_ASSETS_DIR / filename
    f.save(str(dest))
    _save_setting(f"{field}_filename", filename)
    return jsonify({"ok": True, "filename": filename, "url": f"/brand/assets/{filename}"})


# ── GitHub Actions ────────────────────────────────────────────────────────────

def _gh_token() -> str:
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        token = db.setting("GITHUB_TOKEN", "")
    return token


def _gh_headers() -> dict:
    return {
        "Authorization": f"token {_gh_token()}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }


@bp.route("/api/brand/build-status")
@auth.login_required
def brand_build_status():
    import urllib.request
    try:
        url = (f"{_GITHUB_API}/repos/{_GITHUB_REPO}/actions/runs"
               "?per_page=5&event=workflow_dispatch")
        req = urllib.request.Request(url, headers=_gh_headers())
        with urllib.request.urlopen(req, timeout=10) as r:
            data = json.loads(r.read())
        runs = data.get("workflow_runs", [])
        apk_runs = [r for r in runs
                    if "build-apk" in (r.get("path") or "").lower()
                    or "Build" in r.get("name", "")]
        if not apk_runs:
            apk_runs = runs
        if not apk_runs:
            return jsonify({"ok": True, "status": "no_runs", "run": None})
        latest = apk_runs[0]
        run_id     = latest["id"]
        status     = latest["status"]
        conclusion = latest.get("conclusion") or ""
        html_url   = latest.get("html_url", "")
        apk_url    = None
        if status == "completed" and conclusion == "success":
            art_url = (f"{_GITHUB_API}/repos/{_GITHUB_REPO}"
                       f"/actions/runs/{run_id}/artifacts")
            art_req = urllib.request.Request(art_url, headers=_gh_headers())
            with urllib.request.urlopen(art_req, timeout=10) as ar:
                arts = json.loads(ar.read())
            artifacts = arts.get("artifacts", [])
            if artifacts:
                apk_url = artifacts[0].get("archive_download_url")
        return jsonify({
            "ok": True,
            "status": status,
            "conclusion": conclusion,
            "run_id": run_id,
            "html_url": html_url,
            "apk_artifact_url": apk_url,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/api/brand/trigger-build", methods=["POST"])
@auth.login_required
def brand_trigger_build():
    import urllib.request
    data = request.get_json(force=True, silent=True) or {}
    release_tag = data.get("release_tag", "")
    brand_build  = data.get("brand_build", True)
    try:
        payload = json.dumps({
            "ref": "main",
            "inputs": {
                "release_tag": release_tag,
                "brand_build": "true" if brand_build else "false",
            }
        }).encode()
        url = (f"{_GITHUB_API}/repos/{_GITHUB_REPO}"
               "/actions/workflows/build-apk.yml/dispatches")
        req = urllib.request.Request(
            url, data=payload, headers=_gh_headers(), method="POST"
        )
        with urllib.request.urlopen(req, timeout=15) as r:
            code = r.getcode()
        if code == 204:
            return jsonify({"ok": True, "message": "Build triggered successfully"})
        return jsonify({"ok": False, "error": f"GitHub returned {code}"}), 500
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500
