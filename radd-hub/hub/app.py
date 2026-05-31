"""Flask app factory.

Wires every blueprint and starts background threads (mirror retry,
upload watcher, self-heal). Single process, no duplicate dbgen.
"""
from __future__ import annotations
import os
import logging
import threading
from flask import Flask, jsonify
from flask_cors import CORS

# Bootstrap Nix LD_LIBRARY_PATH for Chromium/Playwright BEFORE any imports
# that might indirectly trigger chromium — this is the v2.0 _bootstrap.py port.
try:
    from . import _bootstrap  # noqa: F401
except Exception:
    pass

from . import config, db, keys, auth, mirror, uploader, self_heal, domain_doctor, scheduler

log = logging.getLogger("hub.app")

_BG_STOP = threading.Event()


def create_app() -> Flask:
    config.ensure_dirs()
    config.load_env()
    config.first_run_bootstrap()
    config.setup_logging("raddhub")
    db.init_db()

    # Background scheduler (ongoing series rescan) — off by default, enable via ENABLE_SCHEDULER=1
    if config.get_env_bool("ENABLE_SCHEDULER", False):
        scheduler.start(_BG_STOP)
    # First-time migration from v2 (idempotent)
    if not db.setting("v2_migrated_at"):
        try:
            stats = db.migrate_from_v2()
            log.info("v2 migration: %s", stats)
        except Exception as e:
            log.warning("v2 migration: %s", e)

    # Push vault values into env so legacy modules see them
    keys.export_env_compat()

    app = Flask(
        __name__,
        template_folder=str(config.HUB_DIR / "templates"),
        static_folder=str(config.HUB_DIR / "static"),
    )
    CORS(app)
    _flask_secret = os.environ.get("FLASK_SECRET_KEY") or os.environ.get("SESSION_SECRET")
    if not _flask_secret or len(_flask_secret) < 16:
        # Generate and persist key to DB so sessions survive restarts
        try:
            import secrets as _sec
            _gen = _sec.token_hex(32)
            with db.conn() as _dc:
                _dc.execute("INSERT OR IGNORE INTO settings(k,v) VALUES('flask_secret_key',?)", (_gen,))
                _row = _dc.execute("SELECT v FROM settings WHERE k='flask_secret_key'").fetchone()
                _flask_secret = _row["v"] if _row else _gen
        except Exception:
            import secrets as _sec
            _flask_secret = _sec.token_hex(32)
            log.warning("Could not persist flask_secret_key to DB")
    app.config["SECRET_KEY"] = _flask_secret
    app.config["JSON_SORT_KEYS"] = False
    app.config["MAX_CONTENT_LENGTH"] = 50 * 1024**3  # 50GB

    # ----- blueprints --------------------------------------------------
    from .routes import home, settings as settings_route, library, scan, upload, \
                        stream, admin, bots, api, db_mgmt, organizer as organizer_route, \
                        tid_panel, app_users_panel, analytics, subscriptions, broadcast, zero_rating, \
                        plans_panel, payment_gateway, mobile_api, \
                        catalog_api, search_api, poster_proxy
    app.register_blueprint(auth.bp,                    url_prefix="/auth")
    app.register_blueprint(home.bp)
    app.register_blueprint(settings_route.bp,          url_prefix="/settings")
    app.register_blueprint(library.bp,                 url_prefix="/library")
    app.register_blueprint(scan.bp,                    url_prefix="/scan")
    app.register_blueprint(upload.bp,                  url_prefix="/upload")
    app.register_blueprint(stream.bp,                  url_prefix="/stream")
    app.register_blueprint(admin.bp,                   url_prefix="/admin")
    app.register_blueprint(bots.bp,                    url_prefix="/bots")
    app.register_blueprint(api.bp,                     url_prefix="/api")
    app.register_blueprint(db_mgmt.bp,                 url_prefix="/api/db_mgmt")
    app.register_blueprint(organizer_route.bp,         url_prefix="/organizer")
    app.register_blueprint(tid_panel.bp,               url_prefix="/tid")
    app.register_blueprint(app_users_panel.bp,        url_prefix="/app-users")
    app.register_blueprint(analytics.bp,               url_prefix="/analytics")
    app.register_blueprint(subscriptions.bp,           url_prefix="/subscriptions")
    app.register_blueprint(broadcast.bp,               url_prefix="/broadcast")
    app.register_blueprint(zero_rating.bp,             url_prefix="/zero-rating")
    app.register_blueprint(plans_panel.bp,            url_prefix="/plans")
    app.register_blueprint(payment_gateway.bp,        url_prefix="/billing")
    # ── Mobile app API (Phase 5-9) ────────────────────────────────────────
    app.register_blueprint(mobile_api.bp_auth,         url_prefix="/api/auth")
    app.register_blueprint(mobile_api.bp_sub,          url_prefix="/api/subscription")
    app.register_blueprint(mobile_api.bp_usage,        url_prefix="/api/usage")
    app.register_blueprint(mobile_api.bp_pay,          url_prefix="/api/payment-methods")
    app.register_blueprint(mobile_api.bp_notif,        url_prefix="/api/notifications")
    app.register_blueprint(mobile_api.bp_hist,         url_prefix="/api/history")
    app.register_blueprint(mobile_api.bp_app,          url_prefix="/api/app")
    app.register_blueprint(mobile_api.bp_rec,          url_prefix="/api")  # BUG-A26: prefix changed from /api/recommend to /api to fix no-slash 401 redirect
    # ── Catalog / Search / Poster (migrated from _watch_prototype) ────────
    app.register_blueprint(catalog_api.bp)   # url_prefix in blueprint: /api/catalog
    app.register_blueprint(search_api.bp)    # url_prefix in blueprint: /api/search
    app.register_blueprint(poster_proxy.poster_proxy_bp)  # /api/poster/*
    # ── Security telemetry (Phase 25.6) ──────────────────────────────────────
    from .routes.security_telemetry import bp_security
    app.register_blueprint(bp_security)   # POST /api/security/tamper-report
                                          # GET  /security/tamper-reports (admin)

    # ------------------------------------------------------------------
    # Download proxy — /d/<remote_id>
    # Users receive obfuscated proxy links; admins get real folder URLs.
    # ------------------------------------------------------------------
    @app.route("/d/<remote_id>")
    def download_proxy(remote_id):
        from flask import redirect, Response
        def _err(title, body, code=404):
            html = (
                f"<!doctype html><html><head><meta charset=utf-8>"
                f"<title>{title}</title>"
                f"<style>body{{font-family:sans-serif;text-align:center;padding:3rem;color:#333}}"
                f"h2{{color:#e53}}</style></head>"
                f"<body><h2>⚠️ {title}</h2><p>{body}</p>"
                f"<p><small>Link ID: {remote_id}</small></p></body></html>"
            )
            return Response(html, status=code, mimetype="text/html")

        try:
            with db.conn() as c:
                row = c.execute(
                    "SELECT id, filename, share_url, download_url, "
                    "remote_folder_id, account_id FROM files "
                    "WHERE remote_id=? OR remote_file_id=? OR fingerprint=? LIMIT 1",
                    (remote_id, remote_id, remote_id)
                ).fetchone()
            if not row:
                return _err("File Not Found",
                            "This download link is invalid or the file has been removed.", 404)
            row = dict(row)
            
            # 1. Check for valid pre-generated stream link (Instant Playback)
            stream_link = db.get_stream_link(row["id"])
            if stream_link:
                db.log_stream_serve(stream_link["id"])
                return redirect(stream_link["download_url"], code=302)

            # 2. Fallback: try to generate on-demand if we have a folder share
            folder_id = row.get("remote_folder_id")
            from . import jazzdrive
            
            # Get folder share URL from title or file
            share_url = row.get("share_url")
            if not share_url:
                with db.conn() as c:
                    t_row = c.execute("SELECT folder_share_url FROM titles WHERE id=?", (row["title_id"],)).fetchone()
                    share_url = t_row["folder_share_url"] if t_row else None
            
            session_err = None
            if share_url:
                res = jazzdrive.generate_direct_link(share_url, target_filename=row["filename"])
                if res.get("ok"):
                    db.save_stream_link(row["id"], res["direct_link"], expires_in=28800, account_id=row.get("account_id"))
                    return redirect(res["direct_link"], code=302)
                else:
                    session_err = res.get("error") or "JazzDrive link generation failed"

            # 3. Last resort: Direct URL from files table
            direct = row.get("download_url") or row.get("share_url") or ""
            if direct:
                return redirect(direct, code=302)

            fname = row.get("filename") or remote_id
            if session_err:
                return _err(
                    "Session Expired",
                    f"Could not generate a download link for <b>{fname}</b>.<br>"
                    f"The JazzDrive session needs to be refreshed — please contact the admin.<br>"
                    f"<small>({session_err})</small>",
                    503,
                )
            return _err("Link Not Ready",
                        f"The download link for <b>{fname}</b> has not been generated yet. "
                        "Please try again shortly.", 503)
        except Exception as _ex:
            return _err("Server Error", str(_ex)[:200], 500)

    @app.route("/migration")
    def migration_checklist():
        from pathlib import Path as _Path
        from flask import send_file as _send_file, abort
        f = _Path(__file__).resolve().parent.parent / "migration_checklist.html"
        if not f.exists():
            abort(404)
        return _send_file(str(f), mimetype="text/html")

    @app.route("/healthz")
    def healthz():
        return jsonify({"ok": True, "version": "3.0.0"})

    @app.route("/readyz")
    def readyz():
        return jsonify({"ok": True})

    # Bot health probe — called by the local WhatsApp bot to check if the hub
    # panel is reachable. No auth needed (local-only, read-only status).
    @app.route("/hub/api/services")
    def hub_api_services():
        from . import db as _db
        try:
            stats = _db.count_library()
        except Exception:
            stats = {}
        return jsonify({
            "ok":      True,
            "service": "radd-hub",
            "version": "3.0.0",
            "library": stats,
        })

    # ----- background workers ------------------------------------------
    from . import downloader

    if config.get_env_bool("ENABLE_MIRROR_RETRY", True):
        threading.Thread(target=mirror.retry_loop,
                         args=(_BG_STOP,), daemon=True,
                         name="mirror-retry").start()
        self_heal.register_thread("mirror-retry", mirror.retry_loop,
                                  (_BG_STOP,), _BG_STOP)

    if config.get_env_bool("ENABLE_UPLOAD_WATCHER", True):
        threading.Thread(target=uploader.watcher_loop,
                         args=(_BG_STOP,), daemon=True,
                         name="upload-watcher").start()
        self_heal.register_thread("upload-watcher", uploader.watcher_loop,
                                  (_BG_STOP,), _BG_STOP)

    if config.get_env_bool("ENABLE_DOWNLOAD_QUEUE", True):
        threading.Thread(target=downloader.queue_loop,
                         args=(_BG_STOP,), daemon=True,
                         name="download-queue").start()
        self_heal.register_thread("download-queue", downloader.queue_loop,
                                  (_BG_STOP,), _BG_STOP)

    if config.get_env_bool("ENABLE_KEEPALIVE", True):
        from . import keepalive
        threading.Thread(target=keepalive.loop,
                         args=(_BG_STOP,), daemon=True,
                         name="keepalive").start()
        self_heal.register_thread("keepalive", keepalive.loop,
                                  (_BG_STOP,), _BG_STOP)

    # ── Startup session refresh ────────────────────────────────────────────────
    # When the app was offline, the JSESSIONID expired (60-min idle timeout).
    # On restart we silently obtain a fresh JSESSIONID — preferring the Android
    # OAuth2 refresh_token (months-long), falling back to raw_accesstoken (~1 h).
    def _startup_refresh():
        import time as _t
        _t.sleep(3)  # let DB init settle
        try:
            from . import jazzdrive as _jd
            accounts = db.list_accounts(hide_secrets=False)
            for acct in accounts:
                if not acct.get("is_active"):
                    continue
                has_rt  = bool(acct.get("refresh_token"))
                has_raw = bool(acct.get("raw_accesstoken"))
                if not has_rt and not has_raw:
                    log.info(
                        "startup_refresh: no credentials for %s — OTP required once to store "
                        "Android refresh_token (gives months-long silent renewal)",
                        acct.get("msisdn")
                    )
                    continue
                result = _jd.refresh_session(account_id=acct["id"])
                if result.get("ok"):
                    msg = result.get("message", "")
                    log.info("startup_refresh: session restored for %s — %s (no OTP needed)",
                             acct.get("msisdn"), msg)
                else:
                    log.warning("startup_refresh: could not restore session for %s: %s",
                                acct.get("msisdn"), result.get("error"))
        except Exception as _e:
            log.warning("startup_refresh error: %s", _e)

    threading.Thread(target=_startup_refresh, daemon=True, name="startup-refresh").start()

    from . import bots as _bot_manager
    threading.Thread(target=_bot_manager.start_all,
                     args=(_BG_STOP,), daemon=True,
                     name="bot-manager").start()
    self_heal.register_thread("bot-manager", _bot_manager.start_all,
                              (_BG_STOP,), _BG_STOP)

    if config.get_env_bool("ENABLE_SELF_HEAL", True):
        threading.Thread(target=self_heal.loop,
                         args=(_BG_STOP,), daemon=True,
                         name="self-heal").start()

    # Domain doctor — disabled by default; use ENABLE_DOMAIN_DOCTOR=1 to run as background loop.
    # On-demand: POST /admin/api/domain-doctor/run
    if config.get_env_bool("ENABLE_DOMAIN_DOCTOR", False):
        threading.Thread(target=domain_doctor.loop,
                         args=(_BG_STOP,), daemon=True,
                         name="domain-doctor").start()

    # Quality upgrade scanner — disabled by default; enable via ENABLE_QUALITY_UPGRADE=1
    if config.get_env_bool("ENABLE_QUALITY_UPGRADE", False):
        def _quality_loop(stop):
            import time as _time
            while not stop.wait(3600):  # scan every hour
                try:
                    from . import radd_quality_upgrade as _qu
                    stats = _qu.scan_once()
                    if stats.get("notified"):
                        log.info("Quality upgrade: %s notified", stats["notified"])
                except Exception as e:
                    log.warning("quality_upgrade: %s", e)
        threading.Thread(target=_quality_loop,
                         args=(_BG_STOP,), daemon=True,
                         name="quality-upgrade").start()

    # Bulk Link Engine — proactively pre-generate stream links for JazzBuzz
    if config.get_env_bool("ENABLE_BULK_LINKS", True):
        from . import bulk_link_engine
        threading.Thread(target=bulk_link_engine.loop,
                         args=(_BG_STOP,), daemon=True,
                         name="bulk-link-engine").start()
        self_heal.register_thread("bulk-link-engine", bulk_link_engine.loop,
                                  (_BG_STOP,), _BG_STOP)

    log.info("Radd Hub v3.0 ready")

    # ── Security headers ─────────────────────────────────────────────────────
    @app.after_request
    def _security_headers(resp):
        resp.headers.setdefault("X-Frame-Options",        "SAMEORIGIN")  # SAMEORIGIN allows admin in iframe if needed
        resp.headers.setdefault("X-Content-Type-Options", "nosniff")
        resp.headers.setdefault("X-XSS-Protection",       "1; mode=block")
        resp.headers.setdefault("Referrer-Policy",         "strict-origin-when-cross-origin")
        resp.headers.pop("Server", None)
        return resp


    # Expose csrf_token() as Jinja2 global (used in templates for CSRF protection)
    from .auth import get_csrf_token
    app.jinja_env.globals["csrf_token"] = get_csrf_token


    # Generic error handlers: no stack traces
    from flask import jsonify as _ej
    @app.errorhandler(400)
    def _e400(e): return _ej({'error': 'bad request'}), 400
    @app.errorhandler(403)
    def _e403(e): return _ej({'error': 'forbidden'}), 403
    @app.errorhandler(404)
    def _e404(e): return _ej({'error': 'not found'}), 404
    @app.errorhandler(405)
    def _e405(e): return _ej({'error': 'method not allowed'}), 405
    @app.errorhandler(500)
    def _e500(e):
        app.logger.error('500: %s', e)
        return _ej({'error': 'internal server error'}), 500
    @app.errorhandler(Exception)
    def _eAny(e):
        app.logger.error('Exception: %s', type(e).__name__)
        return _ej({'error': 'internal error'}), 500

    return app
