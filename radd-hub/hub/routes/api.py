"""Shared JSON endpoints (status, library counts, scraper search, JazzDrive OTP,
WhatsApp bot, TMDB, browser/aria2 health, batch queue, recommendations, and
quality-upgrade subscriptions).

v3.0 adds every missing endpoint from v2.0's gui_app.py that was not ported yet:
  - /api/tmdb/check            — live-validate TMDB key
  - /api/tmdb/recommendations  — TMDB recommendation lookup by title+year
  - /api/library/actor         — filter library by actor name
  - /api/library/genre         — filter library by genre
  - /api/library/director      — filter library by director name
  - /api/health                — detailed health (chromium, AI, aria2, scraper sites)
  - /api/browser/status        — chromium availability
  - /api/browser/install       — trigger playwright chromium install
  - /api/aria2/status          — aria2c availability
  - /api/aria2/install         — trigger aria2 install
  - /api/flix/status           — upload/cloud watch-folder status
  - /api/recommend             — library-seeded TMDB recommendations (radd_recommend)
  - /api/quality-upgrade/subscribe  — subscribe to quality upgrade alerts
  - /api/quality-upgrade/unsubscribe — remove a subscription
  - /api/quality-upgrade/scan  — trigger one upgrade scan pass
  - /api/quality-upgrade/list  — list all subscriptions
  - /api/bot/status            — read/write the bot_status_index table
"""
from __future__ import annotations
import json
import os
import shutil
import time
import re as _re
from flask import Blueprint, jsonify, request
from .. import db, keys, auth, mirror, installer, config

bp = Blueprint("api", __name__)


# ---------------------------------------------------------------------------
# Session keepalive ping (no auth required — just keeps the session cookie alive)
# ---------------------------------------------------------------------------

@bp.route("/ping")
def ping():
    """Silent session-keepalive probe.  No auth, no DB hit, just 200 OK."""
    return jsonify({"ok": True, "ts": int(time.time())})

# ---------------------------------------------------------------------------
# App remote config — served to the Flutter app on startup (no auth required)
# Replaces the GitHub raw URL which stopped working when the repo went private.
# ---------------------------------------------------------------------------

@bp.route('/config')
def app_config():
    """Return the Flutter app remote config (api_base_url, min_version_code).
    No auth required — Flutter fetches this before the user logs in."""
    from .. import config as _cfg
    from .. import db as _db
    jd_delta_row = None
    try:
        with _db.conn() as _c:
            jd_delta_row = _c.execute("SELECT v FROM settings WHERE k='jd_delta_url'").fetchone()
    except Exception:
        pass
    jd_delta_url = (jd_delta_row["v"] if jd_delta_row else None) or ""
    support_whatsapp = _db.setting("SUPPORT_WHATSAPP_NUMBER", "923257719165") or "923257719165"
    return jsonify({
        'api_base_url': 'http://92.4.95.252',
        'min_version_code': 1,
        'update_url': 'https://github.com/raddclub/raddflix-app/releases/latest',
        'jd_delta_url': jd_delta_url,
        'support_whatsapp': support_whatsapp,
        'note': 'Served from Oracle server — edit this route to change server URL',
    })




# ---------------------------------------------------------------------------
# Health badges — lightweight status for every tool (polled by the header UI)
# ---------------------------------------------------------------------------

@bp.route("/health/badges")
@auth.login_required
def health_badges():
    """Return live status badges for Downloader, Flix, JD Indexer, Bot, System."""
    from .. import self_heal as _sh
    return jsonify(_sh.get_health())


@bp.route("/health/full")
@auth.login_required
def health_full():
    """Return detailed system health: threads, domains, disk, DB."""
    import threading as _th
    from .. import self_heal as _sh, domain_doctor as _dd
    import shutil as _su

    alive = [t.name for t in _th.enumerate()]
    try:
        usage    = _su.disk_usage(str(config.CACHE_DIR.parent))
        free_mb  = usage.free // (1024 * 1024)
        total_mb = usage.total // (1024 * 1024)
        disk_pct = round(100 * (1 - usage.free / usage.total), 1)
    except Exception:
        free_mb = total_mb = disk_pct = None

    return jsonify({
        "badges":        _sh.get_health(),
        "threads_alive": alive,
        "domain_health": _dd.get_domain_health(),
        "disk": {"free_mb": free_mb, "total_mb": total_mb, "used_pct": disk_pct},
        "ts":  int(time.time()),
    })


# ---------------------------------------------------------------------------
# JazzDrive main account OTP — sidebar re-login popup
# Delegates to the canonical scanner.send_otp / scanner.verify_otp so that
# ALL OTP paths share one implementation.
# ---------------------------------------------------------------------------

@bp.route("/jd/send-otp", methods=["POST"])
@auth.login_required
def jd_send_otp():
    """Send OTP to the main JazzDrive flix account."""
    data   = request.get_json(force=True, silent=True) or {}
    msisdn = _db.normalize_msisdn(data.get("msisdn"))
    if not msisdn:
        return jsonify({"ok": False, "error": "msisdn required"}), 400
    from .. import scanner as _scanner
    aid = _db.upsert_account(msisdn=msisdn, label=f"JazzDrive {msisdn}", role="flix")
    return jsonify(_scanner.send_otp(aid))


@bp.route("/jd/verify-otp", methods=["POST"])
@auth.login_required
def jd_verify_otp():
    """Verify OTP for the main JazzDrive flix account."""
    data   = request.get_json(force=True, silent=True) or {}
    msisdn = _db.normalize_msisdn(data.get("msisdn"))
    otp    = (data.get("otp")    or "").strip()
    if not otp:
        return jsonify({"ok": False, "error": "otp required"}), 400
    from .. import scanner as _scanner
    with _db.conn() as _c:
        row = _c.execute(
            "SELECT id FROM accounts WHERE msisdn=? AND role='flix' LIMIT 1", (msisdn,)
        ).fetchone()
    if not row:
        return jsonify({"ok": False, "error": f"No pending OTP for {msisdn} — send OTP first"}), 400
    return jsonify(_scanner.verify_otp(row["id"], otp))


@bp.route("/jd/retrigger-uploads", methods=["POST"])
@auth.login_required
def jd_retrigger_uploads():
    """Re-trigger upload of any pending (is_ready=0) files in the media directory."""
    from .. import uploader as _up
    n = _up.trigger_scan_now()
    return jsonify({"ok": True, "queued": n})


@bp.route("/jd/status")
@auth.login_required
def jd_full_status():
    """JazzDrive session status + pending upload count."""
    from .. import jazzdrive as _jd
    jd_st = _jd.get_status()
    pending = 0
    try:
        with db.conn() as c:
            row = c.execute("SELECT count(*) FROM files WHERE is_ready=0").fetchone()
            pending = int(row[0]) if row else 0
    except Exception:
        pass
    return jsonify({**jd_st, "pending_uploads": pending})


# ---------------------------------------------------------------------------
# Keepalive worker status
# ---------------------------------------------------------------------------

@bp.route("/keepalive/status")
@auth.login_required
def keepalive_status():
    """Return per-account JazzDrive keepalive status from the background worker."""
    try:
        from .. import keepalive as _ka
        data = _ka.get_status()
        # Enrich with account display names from DB
        accounts_meta = {str(a["id"]): a["msisdn"] for a in db.list_accounts()}
        for aid, v in data.get("accounts", {}).items():
            v.setdefault("msisdn", accounts_meta.get(aid, aid))
            # Compute a simple overall status string for easy UI rendering
            cf = v.get("consecutive_failures", 0)
            tok = v.get("token_status", "unknown")
            if tok == "expired":
                v["status"] = "expired"
            elif cf >= 2:
                v["status"] = "dead"
            elif tok == "expiring_soon":
                v["status"] = "expiring_soon"
            elif v.get("last_ok_at"):
                v["status"] = "ok"
            else:
                v["status"] = "unknown"
        return jsonify(data)
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Server status
# ---------------------------------------------------------------------------

@bp.route("/warmup")
@auth.login_required
def warmup():
    """Pre-generate direct stream links for top 20 titles on app launch."""
    try:
        from .. import jazzdrive
        limit = int(request.args.get("limit", 20))
        
        # 1. Get top titles
        with db.conn() as c:
            titles = c.execute(
                "SELECT id, title, folder_share_url FROM titles "
                "WHERE folder_share_url IS NOT NULL AND folder_share_url != '' "
                "ORDER BY updated_at DESC LIMIT ?", (limit,)
            ).fetchall()
        
        results = []
        for t in titles:
            # 2. Get first file for this title
            files = db.list_files_for_title(t["id"])
            if not files:
                continue
            
            # Pick first episode or movie
            f = files[0]
            
            # 3. Check for existing valid link
            existing = db.get_stream_link(f["id"])
            if existing:
                results.append({"title": t["title"], "file_id": f["id"], "status": "cached"})
                continue
            
            # 4. Generate fresh link
            # Use the folder share URL from the title
            share_url = t["folder_share_url"]
            if share_url:
                res = jazzdrive.generate_direct_link(share_url, target_filename=f["filename"])
                if res.get("ok"):
                    db.save_stream_link(
                        f["id"], res["direct_link"], 
                        expires_in=28800, # 8 hours
                        account_id=f.get("account_id")
                    )
                    results.append({"title": t["title"], "file_id": f["id"], "status": "generated"})
                else:
                    results.append({"title": t["title"], "file_id": f["id"], "status": "error", "err": res.get("error")})
                    
        return jsonify({"ok": True, "results": results})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Enhanced health endpoint (v2-compatible)
# ---------------------------------------------------------------------------

@bp.route("/health")
@auth.login_required
def health():
    """Detailed health check: chromium, AI router, aria2, scraper sites."""
    out: dict = {
        "ok": True,
        "version": "3.0.0",
        "ts": int(time.time()),
        "chromium": False,
        "chromium_error": None,
        "aria2": bool(shutil.which("aria2c")),
        "ai_providers": {},
        "scraper_sites": [],
        "library": db.count_library(),
        "accounts": len(db.list_accounts()),
    }

    # Chromium check — honour the bootstrap-installed executable path if set
    _chromium_exe = os.environ.get("RADD_CHROMIUM_EXECUTABLE") or None
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            try:
                b = pw.chromium.launch(headless=True,
                                       **({"executable_path": _chromium_exe}
                                          if _chromium_exe else {}))
                b.close()
                out["chromium"] = True
            except Exception as e:
                out["chromium_error"] = str(e)[:200]
    except ImportError:
        out["chromium_error"] = "playwright not installed"
    except Exception as e:
        out["chromium_error"] = str(e)[:200]

    # AI providers check
    for provider in ("groq", "gemini", "openai", "openrouter"):
        key_val = keys.get_active_value(provider)
        out["ai_providers"][provider] = bool(key_val)
    # Also count TMDB/OMDB keys
    out["tmdb_keys"] = sum(1 for _ in [keys.get_active_value("tmdb")] if _)
    out["omdb_keys"] = sum(1 for _ in [keys.get_active_value("omdb")] if _)

    # Scraper sites check
    try:
        from .. import sites as _sites
        out["scraper_sites"] = [p.get("name", "") for p in _sites.list_plugins()]
    except Exception:
        pass

    return jsonify(out)




# ─────────────────────────────────────────────────────────────────────────────
# Metadata auto-fix  — enrich titles that are missing posters/plot/ratings
# ─────────────────────────────────────────────────────────────────────────────

_autofix_state: dict = {"running": False, "total": 0, "done": 0, "fixed": 0, "errors": 0, "current": ""}


@bp.route("/meta/autofix/status")
@auth.login_required
def meta_autofix_status():
    """Return progress of the currently running (or last) metadata auto-fix job."""
    return jsonify({**_autofix_state, "ok": True})


@bp.route("/meta/autofix", methods=["POST"])
@auth.login_required
def meta_autofix():
    """Background job: enrich all titles with confidence below threshold.

    Body JSON (all optional):
        threshold   int   0-100  (default 70)  — only fix titles below this score
        limit       int          (default 200) — max titles to process per run
        force       bool         (default false) — re-enrich even if confidence >= threshold
    """
    import threading as _thr
    global _autofix_state
    if _autofix_state.get("running"):
        return jsonify({"ok": False, "error": "Auto-fix already running",
                        "state": _autofix_state}), 409

    data      = request.get_json(force=True, silent=True) or {}
    threshold = int(data.get("threshold", 70))
    limit     = int(data.get("limit", 200))
    force     = bool(data.get("force", False))

    with db.conn() as c:
        q = "SELECT id, title, year, media_type, language, tmdb_id, imdb_id, confidence FROM titles WHERE is_published=1"
        if not force:
            q += f" AND (confidence IS NULL OR confidence < {threshold})"
        q += f" ORDER BY confidence ASC LIMIT {limit}"
        rows = c.execute(q).fetchall()

    _autofix_state = {"running": True, "total": len(rows), "done": 0, "fixed": 0, "errors": 0, "current": ""}

    def _worker():
        global _autofix_state
        from .. import metadata as _meta, keys as _keys

        tmdb_key = _keys.get_active_value("tmdb")
        omdb_key = _keys.get_active_value("omdb")

        for row in rows:
            if not _autofix_state.get("running"):
                break
            title = row["title"] or "Unknown"
            _autofix_state["current"] = title
            try:
                meta_input = {k: row[k] for k in row.keys()}
                enriched   = _meta.enrich_title(meta_input, tmdb_key=tmdb_key, omdb_key=omdb_key)

                updates, vals = [], []
                for col in ("title", "year", "plot", "genres", "genres_csv",
                             "director", "runtime", "country",
                             "poster", "backdrop", "tmdb_id", "imdb_id",
                             "rating", "imdb_rating", "vote_count", "status",
                             "season_count", "episode_count", "trailer_url",
                             "industry", "slug", "confidence", "original_title",
                             "release_date"):
                    new_val = enriched.get(col)
                    old_val = row.get(col) if col in row.keys() else None
                    # Never blank out a previously-set field
                    if new_val is None or new_val == "" or new_val == "[]":
                        continue
                    if old_val not in (None, "", "[]", 0) and col != "confidence":
                        continue
                    updates.append(f"{col}=?")
                    vals.append(new_val)

                if updates:
                    vals.append(int(time.time()))
                    vals.append(row["id"])
                    with db.conn() as c:
                        c.execute(
                            f"UPDATE titles SET {', '.join(updates)}, updated_at=? WHERE id=?",
                            vals
                        )
                    _autofix_state["fixed"] += 1
            except Exception as e:
                import logging as _lg
                _lg.getLogger("hub.meta_autofix").warning("Failed %r: %s", title, e)
                _autofix_state["errors"] += 1

            _autofix_state["done"] += 1
            time.sleep(0.4)   # gentle rate-limit for external APIs

        _autofix_state["running"]  = False
        _autofix_state["current"]  = ""

    thr = _thr.Thread(target=_worker, daemon=True, name="meta-autofix")
    thr.start()

    return jsonify({"ok": True, "queued": len(rows), "state": _autofix_state})


@bp.route("/meta/autofix/stop", methods=["POST"])
@auth.login_required
def meta_autofix_stop():
    """Abort a running auto-fix job."""
    _autofix_state["running"] = False
    return jsonify({"ok": True})


# ─────────────────────────────────────────────────────────────────────────────
# Queue status for Flutter admin screen (JWT-authenticated)
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/queue/status")
def queue_status():
    """Return active + recent download jobs for the Flutter admin screen.
    No auth required — queue info is not sensitive (no credentials exposed).
    """
    try:
        with db.conn() as c:
            jobs = c.execute(
                "SELECT job_id, movie, site, status, progress, message, url, created_at, updated_at "
                "FROM queue ORDER BY updated_at DESC LIMIT 40"
            ).fetchall()
        return jsonify({
            "ok": True,
            "jobs": [dict(j) for j in jobs],
            "ts":   int(time.time()),
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ─────────────────────────────────────────────────────────────────────────────
# Scheduled auto-downloads CRUD
# ─────────────────────────────────────────────────────────────────────────────

@bp.route("/schedule/list")
@auth.login_required
def schedule_list():
    from .. import scheduler as _sched
    _sched.ensure_schema()
    return jsonify({"ok": True, "schedules": _sched.list_schedules()})


@bp.route("/schedule/add", methods=["POST"])
@auth.login_required
def schedule_add():
    from .. import scheduler as _sched
    data = request.get_json(force=True, silent=True) or {}
    label = (data.get("label") or "").strip()
    query = (data.get("query") or "").strip()
    if not label or not query:
        return jsonify({"ok": False, "error": "label and query required"}), 400
    sid = _sched.add_schedule(
        label=label, query=query,
        site=data.get("site", "auto"),
        quality=data.get("quality", "1080p"),
        language=data.get("language", "Hindi"),
        season_hint=data.get("season_hint"),
        frequency=data.get("frequency", "daily"),
        day_of_week=data.get("day_of_week"),
    )
    return jsonify({"ok": True, "id": sid})


@bp.route("/schedule/delete", methods=["POST"])
@auth.login_required
def schedule_delete():
    from .. import scheduler as _sched
    data = request.get_json(force=True, silent=True) or {}
    sid  = data.get("id")
    if not sid:
        return jsonify({"ok": False, "error": "id required"}), 400
    _sched.delete_schedule(int(sid))
    return jsonify({"ok": True})


@bp.route("/schedule/toggle", methods=["POST"])
@auth.login_required
def schedule_toggle():
    from .. import scheduler as _sched
    data   = request.get_json(force=True, silent=True) or {}
    sid    = data.get("id")
    active = bool(data.get("active", True))
    if not sid:
        return jsonify({"ok": False, "error": "id required"}), 400
    _sched.toggle_schedule(int(sid), active)
    return jsonify({"ok": True})


@bp.route("/schedule/run-now", methods=["POST"])
@auth.login_required
def schedule_run_now():
    """Immediately trigger one scheduled entry (manual run)."""
    from .. import scheduler as _sched
    data = request.get_json(force=True, silent=True) or {}
    sid  = data.get("id")
    if not sid:
        return jsonify({"ok": False, "error": "id required"}), 400
    # Set next_run_at to 0 so the loop picks it up immediately
    with db.conn() as c:
        c.execute("UPDATE scheduled_downloads SET next_run_at=0 WHERE id=?", (int(sid),))
    _sched.run_scheduled_downloads()
    return jsonify({"ok": True})

# ---------------------------------------------------------------------------
# Doctor
# ---------------------------------------------------------------------------

@bp.route("/doctor")
@auth.login_required
def doctor():
    return jsonify(installer.doctor())


# ---------------------------------------------------------------------------
# Browser (Chromium) endpoints
# ---------------------------------------------------------------------------

@bp.route("/browser/status")
@auth.login_required
def browser_status():
    """Check whether Chromium is available and launchable."""
    ok = False
    error = None
    _chromium_exe = os.environ.get("RADD_CHROMIUM_EXECUTABLE") or None
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as pw:
            try:
                b = pw.chromium.launch(headless=True,
                                       **({"executable_path": _chromium_exe}
                                          if _chromium_exe else {}))
                b.close()
                ok = True
            except Exception as e:
                error = str(e)[:300]
    except ImportError:
        error = "playwright not installed"
    except Exception as e:
        error = str(e)[:300]
    return jsonify({"ok": ok, "available": ok, "error": error})


@bp.route("/browser/install", methods=["POST"])
@auth.login_required
def browser_install():
    """Trigger playwright chromium install (blocking, may take a while)."""
    try:
        ok = installer.ensure_chromium()
        return jsonify({"ok": ok, "message": "Chromium installed" if ok else "Install failed — check logs"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# aria2 endpoints
# ---------------------------------------------------------------------------

@bp.route("/aria2/status")
@auth.login_required
def aria2_status():
    available = bool(shutil.which("aria2c"))
    path = shutil.which("aria2c") or None
    return jsonify({"ok": available, "available": available, "path": path})


@bp.route("/aria2/install", methods=["POST"])
@auth.login_required
def aria2_install():
    """Attempt to install aria2c via OS package manager."""
    try:
        ok = installer.ensure_aria2()
        return jsonify({"ok": ok, "available": bool(shutil.which("aria2c")),
                        "message": "aria2c ready" if ok else "Install failed — install manually"})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# TMDB endpoints (v2 port)
# ---------------------------------------------------------------------------

@bp.route("/tmdb/check", methods=["GET", "POST"])
@auth.login_required
def tmdb_check():
    """Validate the active TMDB key OR search for a movie title.

    Without ?q=: validates the API key (returns ok/error).
    With ?q=<title>: searches TMDB and returns {found, title, year, media_type, rating, tmdb_id}.
    """
    query = (request.args.get("q") or "").strip()
    key_val = keys.get_active_value("tmdb")
    if not key_val:
        return jsonify({"ok": False, "found": None, "error": "No TMDB API key configured"}), 400
    try:
        import requests as _requests
        if not query:
            r = _requests.get(
                "https://api.themoviedb.org/3/configuration",
                params={"api_key": key_val}, timeout=10
            )
            if r.status_code == 200:
                keys.mark_ok("tmdb", key_val)
                img = r.json().get("images", {})
                res = {"ok": True, "message": "TMDB key is valid",
                       "base_url": img.get("secure_base_url", ""),
                       "poster_sizes": img.get("poster_sizes", [])}
                if auth._bot_key_ok():
                    res["api_key"] = key_val
                return jsonify(res)
            keys.mark_invalid("tmdb", key_val)
            return jsonify({"ok": False, "error": f"TMDB returned HTTP {r.status_code}"}), 502

        r = _requests.get(
            "https://api.themoviedb.org/3/search/multi",
            params={"api_key": key_val, "query": query}, timeout=10
        )
        if r.status_code != 200:
            keys.mark_invalid("tmdb", key_val)
            return jsonify({"ok": False, "found": None,
                            "error": f"TMDB HTTP {r.status_code}"}), 502
        results = r.json().get("results", [])
        keys.mark_ok("tmdb", key_val)
        if not results:
            return jsonify({"ok": True, "found": False})
        best = results[0]
        mt   = best.get("media_type", "movie")
        title = best.get("title") or best.get("name") or query
        year  = (best.get("release_date") or best.get("first_air_date") or "")[:4]
        return jsonify({
            "ok":         True,
            "found":      True,
            "tmdb_id":    best.get("id"),
            "media_type": mt,
            "title":      title,
            "year":       year or None,
            "rating":     best.get("vote_average"),
            "poster":     best.get("poster_path"),
        })
    except Exception as e:
        return jsonify({"ok": False, "found": None, "error": str(e)}), 500


@bp.route("/tmdb/recommendations")
@auth.login_required
def tmdb_recommendations():
    """Get TMDB recommendations for a title.
    ?title=Inception&year=2010&tmdb_id=27205&media_type=movie&limit=10
    """
    title      = request.args.get("title", "").strip()
    year       = request.args.get("year", "").strip()
    tmdb_id    = request.args.get("tmdb_id", "").strip()
    media_type = request.args.get("media_type", "movie").strip() or "movie"
    limit      = int(request.args.get("limit", 10))

    key_val = keys.get_active_value("tmdb")
    if not key_val:
        return jsonify({"ok": False, "error": "No TMDB API key configured"}), 400

    try:
        import requests as _requests

        # Resolve tmdb_id if not provided
        if not tmdb_id and title:
            sr = _requests.get(
                "https://api.themoviedb.org/3/search/multi",
                params={"api_key": key_val, "query": title, "year": year or None},
                timeout=10
            )
            results = sr.json().get("results", [])
            if results:
                best = results[0]
                tmdb_id    = str(best.get("id", ""))
                media_type = best.get("media_type", media_type)

        if not tmdb_id:
            return jsonify({"ok": False, "error": "Could not find TMDB ID for this title"}), 404

        # Check recommendation cache
        try:
            with db.conn() as c:
                cached = c.execute(
                    "SELECT payload_json, fetched_at FROM recommendation_cache "
                    "WHERE seed_tmdb_id=? AND media_type=?",
                    (int(tmdb_id), media_type)
                ).fetchone()
            if cached and (time.time() - (cached["fetched_at"] or 0)) < 86400:
                import json as _json
                payload = _json.loads(cached["payload_json"])
                return jsonify({"ok": True, "cached": True,
                                "tmdb_id": tmdb_id, "media_type": media_type,
                                "results": payload[:limit]})
        except Exception:
            pass

        # Fetch from TMDB
        r = _requests.get(
            f"https://api.themoviedb.org/3/{media_type}/{tmdb_id}/recommendations",
            params={"api_key": key_val}, timeout=10
        )
        if r.status_code != 200:
            return jsonify({"ok": False, "error": f"TMDB HTTP {r.status_code}"}), 502

        recs = r.json().get("results", [])[:20]

        # Cache results
        try:
            import json as _json
            with db.conn() as c:
                c.execute(
                    "INSERT OR REPLACE INTO recommendation_cache "
                    "(seed_tmdb_id, media_type, payload_json, fetched_at) VALUES(?,?,?,?)",
                    (int(tmdb_id), media_type, _json.dumps(recs), int(time.time()))
                )
        except Exception:
            pass

        keys.mark_ok("tmdb", key_val)
        return jsonify({"ok": True, "cached": False,
                        "tmdb_id": tmdb_id, "media_type": media_type,
                        "results": recs[:limit]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Library count + overview
# ---------------------------------------------------------------------------

@bp.route("/library/overview")
@auth.login_required
def lib_overview():
    return jsonify(db.count_library())


@bp.route("/library/counts")
@auth.login_required
def lib_counts():
    """Alias for /library/overview — returns file/title counts."""
    return jsonify(db.count_library())


@bp.route("/library/recent")
@auth.login_required
def lib_recent():
    """Return recently added files. ?limit=20"""
    limit = min(int(request.args.get("limit", 20)), 200)
    try:
        files = db.list_files(limit=limit)
        return jsonify({"ok": True, "count": len(files), "files": files})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Library filter endpoints (v2 port)
# ---------------------------------------------------------------------------

@bp.route("/library/actor")
@auth.login_required
def lib_by_actor():
    """Filter library titles by actor name. ?name=Shah+Rukh+Khan&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT * FROM titles WHERE cast_json LIKE ? ORDER BY rating DESC LIMIT ?",
                (f"%{name}%", limit)
            ).fetchall()
        return jsonify({"ok": True, "actor": name, "count": len(rows),
                        "results": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/library/genre")
@auth.login_required
def lib_by_genre():
    """Filter library titles by genre. ?name=Action&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT * FROM titles WHERE genres_csv LIKE ? ORDER BY rating DESC LIMIT ?",
                (f"%{name}%", limit)
            ).fetchall()
        return jsonify({"ok": True, "genre": name, "count": len(rows),
                        "results": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/library/director")
@auth.login_required
def lib_by_director():
    """Filter library titles by director name. ?name=Christopher+Nolan&limit=50"""
    name  = request.args.get("name", "").strip()
    limit = int(request.args.get("limit", 50))
    if not name:
        return jsonify({"ok": False, "error": "Missing ?name= parameter"}), 400
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT * FROM titles WHERE director LIKE ? ORDER BY rating DESC LIMIT ?",
                (f"%{name}%", limit)
            ).fetchall()
        return jsonify({"ok": True, "director": name, "count": len(rows),
                        "results": [dict(r) for r in rows]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/library/has")
@auth.login_required
def lib_has():
    """Check if a title is already in the library. ?q=Inception or ?title=Inception&year=2010"""
    title = (request.args.get("q") or request.args.get("title", "")).strip()
    year  = request.args.get("year", "").strip()
    if not title:
        return jsonify({"ok": False, "error": "Missing ?q= parameter"}), 400
    try:
        with db.conn() as c:
            sql  = "SELECT id, title, year FROM titles WHERE title LIKE ?"
            args = [f"%{title}%"]
            if year:
                sql  += " AND year LIKE ?"
                args.append(f"{year}%")
            row = c.execute(sql, args).fetchone()
        if row:
            return jsonify({"ok": True, "has": True, "title": dict(row)})
        return jsonify({"ok": True, "has": False})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Flix / upload cloud status (v2 port)
# ---------------------------------------------------------------------------

@bp.route("/flix/status")
@auth.login_required
def flix_status():
    """Upload/cloud watch-folder status (ported from v2 /api/cloud/status)."""
    media_dir = config.MEDIA_DIR
    out = {
        "watch_folder": str(media_dir),
        "pending": [],
        "recent_uploads": [],
        "accounts": len(db.list_accounts()),
    }
    try:
        if media_dir.is_dir():
            for p in sorted(media_dir.rglob("*")):
                if p.is_file() and not p.name.startswith("."):
                    st = p.stat()
                    out["pending"].append({
                        "name":  p.name,
                        "size":  st.st_size,
                        "mtime": int(st.st_mtime),
                    })
    except Exception:
        pass
    try:
        with db.conn() as c:
            rows = c.execute(
                "SELECT filename, size_bytes, uploaded_at, share_url, "
                "       (SELECT title FROM titles WHERE id=files.title_id) AS title "
                "FROM files WHERE source='upload' "
                "ORDER BY uploaded_at DESC LIMIT 25"
            ).fetchall()
        out["recent_uploads"] = [dict(r) for r in rows]
    except Exception:
        pass
    return jsonify(out)


# ---------------------------------------------------------------------------
# Mirror
# ---------------------------------------------------------------------------

@bp.route("/mirror/push-all", methods=["POST"])
@auth.login_required
def push_all():
    """Force-push every unsynced file."""
    n_pushed = 0
    with db.conn() as c:
        rows = c.execute(
            "SELECT id FROM files WHERE github_status IS NULL OR github_status='failed' "
            "OR gsheets_status IS NULL OR gsheets_status='failed'"
        ).fetchall()
    for r in rows:
        try:
            mirror.push_file(r["id"])
            n_pushed += 1
        except Exception:
            pass
    return jsonify({"pushed": n_pushed})


# ---------------------------------------------------------------------------
# Scraper search endpoints
# ---------------------------------------------------------------------------

@bp.route("/scraper/search")
@auth.login_required
def scraper_search():
    """Search all movie sites. ?q=title&year=2023&sites=vegamovies,rogmovies"""
    q        = request.args.get("q", "").strip()
    year     = request.args.get("year", "").strip()
    sites_arg = request.args.get("sites", "")
    sites = [s.strip() for s in sites_arg.split(",") if s.strip()] if sites_arg else None
    if not q:
        return jsonify({"ok": False, "error": "Missing ?q= parameter"}), 400
    try:
        from ..scrapers import search_all
        results = search_all(q, year=year, sites=sites, timeout=25)
        return jsonify({"ok": True, "query": q, "year": year,
                        "count": len(results), "results": results})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/scraper/links")
@auth.login_required
def scraper_links():
    """Get download links for a page. ?url=...&site=vegamovies"""
    page_url = request.args.get("url", "").strip()
    site     = request.args.get("site", "").strip()
    if not page_url or not site:
        return jsonify({"ok": False, "error": "Missing ?url= or ?site= parameter"}), 400
    try:
        from ..scrapers import get_links
        links = get_links(page_url, site)
        return jsonify({"ok": True, "url": page_url, "site": site,
                        "count": len(links), "links": links})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/search/test", methods=["POST"])
@auth.login_required
def scraper_test():
    """Test search across all sites for a movie. Body: {title, year}"""
    data  = request.get_json(silent=True) or {}
    title = data.get("title", "").strip()
    year  = str(data.get("year", "")).strip()
    sites = data.get("sites")
    if not title:
        return jsonify({"ok": False, "error": "Missing title"}), 400
    try:
        from ..scrapers import search_all
        results = search_all(title, year=year, sites=sites, timeout=30)
        by_site: dict = {}
        for r in results:
            s = r.get("site", "unknown")
            by_site.setdefault(s, []).append(r)
        return jsonify({
            "ok": True, "title": title, "year": year,
            "total": len(results),
            "by_site": {k: len(v) for k, v in by_site.items()},
            "results": results,
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# JazzDrive OTP / session endpoints
# ---------------------------------------------------------------------------

@bp.route("/jazzdrive/status")
@auth.login_required
def jd_status():
    try:
        from ..jazzdrive import get_status
        return jsonify(get_status())
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 500


@bp.route("/jazzdrive/otp/trigger", methods=["POST"])
@auth.login_required
def jd_otp_trigger():
    data   = request.get_json(silent=True) or {}
    msisdn = data.get("msisdn", "").strip() or db.setting("JAZZDRIVE_MSISDN") or ""
    try:
        from ..jazzdrive import trigger_otp_flow
        return jsonify(trigger_otp_flow(msisdn))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/jazzdrive/otp/resend", methods=["POST"])
@auth.login_required
def jd_otp_resend():
    try:
        from ..jazzdrive import resend_otp
        return jsonify(resend_otp())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/jazzdrive/otp/verify", methods=["POST"])
@auth.login_required
def jd_otp_verify():
    data = request.get_json(silent=True) or {}
    otp  = str(data.get("otp", "")).strip()
    if not otp:
        return jsonify({"ok": False, "error": "OTP is required"}), 400
    try:
        from ..jazzdrive import submit_otp
        return jsonify(submit_otp(otp))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/jazzdrive/refresh", methods=["POST"])
@auth.login_required
def jd_refresh():
    """Silently refresh the JazzDrive session using the stored raw_accesstoken.

    No OTP required. Uses the raw_accesstoken decoded from the original login
    response to obtain a fresh JSESSIONID + validationKey from the server.

    Optional body: { "account_id": <int> } to refresh a specific account.
    Omit body (or pass {}) to refresh the default account from session file.

    Returns:
      {"ok": true,  "message": "...", "validation_key": "...", "jsessionid": "..."}
      {"ok": false, "error": "..."}  — OTP re-login required if raw_accesstoken missing
    """
    data       = request.get_json(silent=True) or {}
    account_id = data.get("account_id") or None
    try:
        from ..jazzdrive import refresh_session
        result = refresh_session(account_id=account_id)
        status = 200 if result.get("ok") else 503
        return jsonify(result), status
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/jazzdrive/upload", methods=["POST"])
@auth.login_required
def jd_upload():
    data     = request.get_json(silent=True) or {}
    filename = data.get("filename", "").strip()
    if not filename:
        return jsonify({"ok": False, "error": "filename required"}), 400
    file_path = config.MEDIA_DIR / filename
    try:
        from ..jazzdrive import upload_file_to_jazzdrive
        return jsonify(upload_file_to_jazzdrive(file_path))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/jazzdrive/tokens", methods=["POST"])
@auth.login_required
def jd_save_tokens():
    """Save JazzDrive tokens directly (paste from browser DevTools).

    Body: { "validation_key": "...", "jsessionid": "...", "msisdn": "..." }
    """
    data = request.get_json(silent=True) or {}
    vk   = (data.get("validation_key") or data.get("validationkey") or "").strip()
    jid  = (data.get("jsessionid") or data.get("JSESSIONID") or "").strip()
    msisdn = _db.normalize_msisdn(data.get("msisdn")) or None
    if not vk or not jid:
        return jsonify({"ok": False, "error": "validation_key and jsessionid are required"}), 400
    try:
        from ..jazzdrive import save_tokens_direct
        return jsonify(save_tokens_direct(vk, jid, msisdn))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# WhatsApp Bot endpoints
# ---------------------------------------------------------------------------

@bp.route("/whatsapp/status")
@auth.login_required
def wa_status():
    try:
        from ..bots.whatsapp import get_status
        return jsonify(get_status())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/whatsapp/start", methods=["POST"])
@auth.login_required
def wa_start():
    try:
        from ..bots.whatsapp import start
        return jsonify(start())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/whatsapp/stop", methods=["POST"])
@auth.login_required
def wa_stop():
    try:
        from ..bots.whatsapp import stop
        return jsonify(stop())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/whatsapp/restart", methods=["POST"])
@auth.login_required
def wa_restart():
    try:
        from ..bots.whatsapp import restart
        return jsonify(restart())
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/whatsapp/logs")
@auth.login_required
def wa_logs():
    n = int(request.args.get("n", 100))
    try:
        from ..bots.whatsapp import get_logs
        return jsonify({"ok": True, "lines": get_logs(n)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/whatsapp/pair", methods=["POST"])
@auth.login_required
def wa_pair():
    data  = request.get_json(silent=True) or {}
    phone = data.get("phone", "").strip()
    try:
        from ..bots.whatsapp import request_pairing_code
        return jsonify(request_pairing_code(phone))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Batch queue endpoint
# ---------------------------------------------------------------------------

@bp.route("/batch-queue", methods=["POST"])
@auth.login_required
def batch_queue():
    """Queue multiple movies at once. Body: {movies: ['Title Year', ...], site: 'auto'}"""
    data = request.get_json(silent=True) or {}
    raw  = data.get("movies", [])
    site = data.get("site", "auto")
    if not raw:
        return jsonify({"ok": False, "error": "No movies provided"}), 400
    import uuid as _uuid
    queued  = []
    skipped = []
    now     = int(time.time())
    
    from .. import downloader as _dl
    for line in raw:
        line = line.strip()
        if not line:
            continue
            
        parsed = _dl.parse_movie_query(line)
        title = parsed.get("title", line) if isinstance(parsed, dict) else getattr(parsed, "title", line)
        year  = parsed.get("year_hint") if isinstance(parsed, dict) else getattr(parsed, "year", None)
        movie_key = f"{title} {year}".strip() if year else title
        
        # --- Duplicate Check ---
        dup = db.check_duplicate(title, year)
        if dup:
            skipped.append({"movie": movie_key, "reason": dup["reason"], "ok": True})
            continue
        # -----------------------

        try:
            jid = _uuid.uuid4().hex[:10]
            with db.conn() as c:
                c.execute(
                    "INSERT INTO queue(job_id,movie,site,status,created_at,updated_at) VALUES(?,?,?,?,?,?)",
                    (jid, movie_key, site, "queued", now, now)
                )
            queued.append({"movie": movie_key, "job_id": jid, "ok": True})
        except Exception as e:
            skipped.append({"movie": movie_key, "ok": False, "error": str(e)})
    return jsonify({"ok": True, "queued": len(queued), "skipped": len(skipped),
                    "jobs": queued, "errors": skipped})


# /api/recommend is now handled by mobile_api.bp_rec with JWT auth

# ---------------------------------------------------------------------------
# Quality upgrade subscriptions  (radd_quality_upgrade — ported from v2)
# ---------------------------------------------------------------------------

@bp.route("/quality-upgrade/subscribe", methods=["POST"])
@auth.login_required
def quality_upgrade_subscribe():
    """Subscribe to quality upgrade alerts.

    Body: {user_jid, fingerprint, current_q, target_q}
    """
    data        = request.get_json(silent=True) or {}
    user_jid    = (data.get("user_jid") or "").strip()
    fingerprint = (data.get("fingerprint") or "").strip()
    current_q   = (data.get("current_q") or "").strip().lower()
    target_q    = (data.get("target_q") or "1080p").strip().lower()
    if not fingerprint:
        return jsonify({"ok": False, "error": "fingerprint required"}), 400
    try:
        from ..radd_quality_upgrade import subscribe
        ok = subscribe(user_jid, fingerprint, current_q, target_q)
        return jsonify({"ok": ok, "fingerprint": fingerprint,
                        "current_q": current_q, "target_q": target_q})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/quality-upgrade/unsubscribe", methods=["POST"])
@auth.login_required
def quality_upgrade_unsubscribe():
    """Remove a quality upgrade subscription.

    Body: {user_jid, fingerprint}
    """
    data        = request.get_json(silent=True) or {}
    user_jid    = (data.get("user_jid") or "").strip()
    fingerprint = (data.get("fingerprint") or "").strip()
    if not fingerprint:
        return jsonify({"ok": False, "error": "fingerprint required"}), 400
    try:
        from ..radd_quality_upgrade import unsubscribe
        ok = unsubscribe(user_jid, fingerprint)
        return jsonify({"ok": ok})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/quality-upgrade/list")
@auth.login_required
def quality_upgrade_list():
    """List all quality upgrade subscriptions."""
    try:
        from ..radd_quality_upgrade import list_subscriptions
        subs = list_subscriptions()
        return jsonify({"ok": True, "subscriptions": subs, "count": len(subs)})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/quality-upgrade/scan", methods=["POST"])
@auth.login_required
def quality_upgrade_scan():
    """Trigger one quality upgrade scan pass.

    Optionally accepts a scraper_site override in body: {site: 'auto'}
    Returns {checked, notified, errors, ts}.
    """
    try:
        from ..radd_quality_upgrade import scan_once
        result = scan_once()
        return jsonify({"ok": True, **result})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Bot status index  (bot_status_index table — tracks in-progress bot jobs)
# ---------------------------------------------------------------------------

@bp.route("/bot/status", methods=["GET"])
@auth.login_required
def bot_status_list():
    """List bot_status_index rows.

    Query params:
      user_jid  — filter by WhatsApp JID (optional)
      state     — filter by state (optional)
      limit     — max rows (default 100)
    """
    user_jid = request.args.get("user_jid") or None
    state    = request.args.get("state")    or None
    try:
        limit = min(int(request.args.get("limit", 100)), 500)
    except (TypeError, ValueError):
        limit = 100
    rows = db.list_bot_status(user_jid=user_jid, state=state, limit=limit)
    return jsonify({"ok": True, "rows": rows, "count": len(rows)})


@bp.route("/bot/status", methods=["POST"])
@auth.login_required
def bot_status_upsert():
    """Upsert a bot_status_index row.

    Body: {fingerprint, user_jid?, title?, state?, progress_pct?, detail?}
    """
    data = request.get_json(silent=True) or {}
    fp   = (data.get("fingerprint") or "").strip()
    if not fp:
        return jsonify({"ok": False, "error": "fingerprint required"}), 400
    try:
        db.upsert_bot_status(
            fp,
            user_jid     = data.get("user_jid", ""),
            title        = data.get("title", ""),
            state        = data.get("state", "pending"),
            progress_pct = float(data.get("progress_pct") or 0),
            detail       = data.get("detail", ""),
        )
        return jsonify({"ok": True, "fingerprint": fp})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


@bp.route("/bot/status/<fingerprint>", methods=["DELETE"])
@auth.login_required
def bot_status_delete(fingerprint: str):
    """Delete a single bot_status_index row by fingerprint."""
    db.delete_bot_status(fingerprint)
    return jsonify({"ok": True})


# ---------------------------------------------------------------------------
# OTP status / submit — called by the local WhatsApp bot subprocess.
# No session auth required (localhost-to-localhost, read-only state file).
# ---------------------------------------------------------------------------

_OTP_STATE_FILE = config.TEMP_DIR / "radd_jd_otp_state.json"

def _read_otp_state() -> dict:
    """Read the JazzDrive OTP state from the shared temp file."""
    from pathlib import Path as _Path
    import json as _json
    try:
        if _OTP_STATE_FILE.exists():
            return _json.loads(_OTP_STATE_FILE.read_text())
    except Exception:
        pass
    return {}


@bp.route("/otp/status")
def otp_status():
    """Return the current JazzDrive OTP state (used by the WhatsApp bot)."""
    state = _read_otp_state()
    return jsonify({
        "ok":      True,
        "pending": bool(state),
        "state":   state,
        "ts":      int(time.time()),
    })


@bp.route("/otp/submit", methods=["POST"])
def otp_submit():
    """Submit an OTP code (used by the WhatsApp bot).

    Body: {otp: "1234"}
    Delegates to jazzdrive.submit_otp and returns the result.
    """
    data = request.get_json(silent=True) or {}
    otp  = str(data.get("otp", "")).strip()
    if not otp:
        return jsonify({"ok": False, "error": "otp required"}), 400
    try:
        from ..jazzdrive import submit_otp
        return jsonify(submit_otp(otp))
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500


# ---------------------------------------------------------------------------
# Library export  (ported from v1.0 export feature)
# ---------------------------------------------------------------------------

@bp.route("/export/catalog")
@auth.login_required
def export_catalog():
    """Export the full library catalog as CSV or JSON.

    Query params:
      fmt   — 'csv' or 'json' (default 'json')
      type  — optional filter: movie / series / anime
    """
    import csv
    import io
    fmt         = (request.args.get("fmt") or "json").lower().strip()
    filter_type = (request.args.get("type") or "").strip().lower()

    sql  = ("SELECT t.id, t.title, t.year, t.media_type, t.genres_csv, t.director, t.rating, "
            "       t.tmdb_id, t.poster, t.created_at, "
            "       f.filename, f.share_url, f.size_bytes, f.quality, f.source "
            "FROM titles t LEFT JOIN files f ON f.title_id = t.id ")
    params: list = []
    if filter_type:
        sql    += "WHERE t.media_type = ? "
        params.append(filter_type)
    sql += "ORDER BY t.title COLLATE NOCASE"

    with db.conn() as c:
        rows = [dict(r) for r in c.execute(sql, params).fetchall()]

    if fmt == "csv":
        out = io.StringIO()
        fieldnames = [
            "id", "title", "year", "media_type", "genres_csv", "director", "rating",
            "tmdb_id", "filename", "share_url", "size_bytes", "quality",
            "source", "created_at",
        ]
        w = csv.DictWriter(out, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow(r)
        csv_bytes = out.getvalue().encode("utf-8")
        from flask import Response
        return Response(
            csv_bytes,
            mimetype="text/csv",
            headers={"Content-Disposition": "attachment; filename=radd_catalog.csv"},
        )

    return jsonify({"ok": True, "count": len(rows), "catalog": rows})


# ---------------------------------------------------------------------------
# WhatsApp broadcast  (ported from v2.0 admin broadcast feature)
# ---------------------------------------------------------------------------

@bp.route("/whatsapp/broadcast", methods=["POST"])
@auth.login_required
def whatsapp_broadcast():
    """Send a broadcast message to all verified WhatsApp bot users.

    Body: {message: str, roles: ['verified'] (optional)}
    Returns: {ok, sent, failed, errors}
    """
    import json as _json
    data    = request.get_json(silent=True) or {}
    message = (data.get("message") or "").strip()
    roles   = data.get("roles") or ["verified"]
    if not message:
        return jsonify({"ok": False, "error": "message required"}), 400
    if isinstance(roles, str):
        roles = [roles]

    # Read users from bot users.json
    try:
        from ..bots import whatsapp as _wa_mgr
        users_path = getattr(_wa_mgr, "_BOT_USERS_FILE",
                             config.PROJECT_ROOT / "bots" / "whatsapp" / "users.json")
        user_data = _json.loads(Path(users_path).read_text()) if Path(users_path).exists() else {}
    except Exception:
        user_data = {}

    # Collect unique JIDs from requested roles
    jids: list[str] = []
    for role in roles:
        for entry in (user_data.get(role) or []):
            jid = entry if "@" in str(entry) else f"{entry}@s.whatsapp.net"
            if jid not in jids:
                jids.append(jid)

    if not jids:
        return jsonify({"ok": True, "sent": 0, "failed": 0,
                        "errors": [], "message": "No users in specified roles"})

    sent   = 0
    failed = 0
    errors = []
    try:
        from ..bots.whatsapp import send_message as _wa_send
    except Exception:
        _wa_send = None

    for jid in jids:
        try:
            if _wa_send:
                _wa_send(jid, message)
            else:
                import uuid as _uuid
                cmd_dir = config.PROJECT_ROOT / "bots" / "whatsapp" / "bot-cmd"
                cmd_dir.mkdir(parents=True, exist_ok=True)
                cmd_file = cmd_dir / f"send_{_uuid.uuid4().hex[:8]}.json"
                cmd_file.write_text(_json.dumps({"action": "send", "jid": jid, "message": message}))
            sent += 1
        except Exception as e:
            failed += 1
            errors.append({"jid": jid, "error": str(e)})

    return jsonify({
        "ok":     True,
        "sent":   sent,
        "failed": failed,
        "total":  len(jids),
        "errors": errors[:20],
    })


# ---------------------------------------------------------------------------
# 3-way GitHub / Google Sheets sync  (ported from v1.0)
# ---------------------------------------------------------------------------

@bp.route("/sync", methods=["POST"])
@auth.login_required
def api_sync():
    """Trigger a full-DB push to GitHub and/or Google Sheets.

    Body (JSON, all optional):
      mode      — 'github' | 'gsheets' | 'both'  (default 'both')
      fingerprint — if set, sync only that single file entry
    """
    data = request.get_json(force=True, silent=True) or {}
    mode        = str(data.get("mode", "both")).lower()
    fingerprint = (data.get("fingerprint") or "").strip()

    if mode not in ("github", "gsheets", "both"):
        return jsonify({"error": "mode must be 'github', 'gsheets', or 'both'"}), 400

    try:
        from ..sync import sync_all, sync_entry, status as sync_status
    except ImportError as e:
        return jsonify({"error": f"sync module unavailable: {e}"}), 500

    if fingerprint:
        result = sync_entry(fingerprint)
    else:
        result = sync_all(mode=mode)

    status_snapshot = sync_status()
    result["status"] = status_snapshot
    return jsonify(result)


@bp.route("/sync/status", methods=["GET"])
@auth.login_required
def api_sync_status():
    """Return mirror health: last sync timestamps, counts, and configuration state."""
    try:
        from ..sync import status as sync_status
        return jsonify(sync_status())
    except ImportError as e:
        return jsonify({"error": f"sync module unavailable: {e}"}), 500


# ---------------------------------------------------------------------------
# Cloudflare Quick Tunnel
# ---------------------------------------------------------------------------

@bp.route("/tunnel/status")
@auth.login_required
def tunnel_status():
    """Return the current Cloudflare tunnel state (running, url, pid, log_tail)."""
    from .. import tunnel as _tn
    return jsonify(_tn.status())


@bp.route("/tunnel/start", methods=["POST"])
@auth.login_required
def tunnel_start():
    """Start a Cloudflare Quick Tunnel.

    Body (optional): {port: 5000}
    Blocks up to 20 s for the public URL to appear, then returns state.
    """
    from .. import tunnel as _tn
    data = request.get_json(silent=True) or {}
    port = int(data.get("port", 5000))
    result = _tn.start(port)
    return jsonify(result)


@bp.route("/tunnel/stop", methods=["POST"])
@auth.login_required
def tunnel_stop():
    """Stop the running Cloudflare tunnel."""
    from .. import tunnel as _tn
    return jsonify(_tn.stop())


# ---------------------------------------------------------------------------
# WhatsApp bot compatibility — /api/queue/add  (alias for POST /api/queue)
# ---------------------------------------------------------------------------

@bp.route("/queue/add", methods=["POST"])
@auth.login_required
def queue_add_alias():
    """Compatibility alias used by the WhatsApp bot (streamApi.js legacy path).

    Accepts {name: ...} or {movie: ...} so both old and new bot versions work.
    Forwards to the stream blueprint's queue_add logic.
    """
    import uuid as _uuid
    data  = request.get_json(force=True, silent=True) or {}
    movie = (data.get("movie") or data.get("name") or "").strip()
    site  = (data.get("site") or "auto").strip()
    if not movie:
        return jsonify({"error": "movie required"}), 400

    # --- Duplicate Check ---
    from .. import downloader as _dl
    parsed = _dl.parse_movie_query(movie)
    clean_name = parsed.get("title", movie) if isinstance(parsed, dict) else getattr(parsed, "title", movie)
    year_hint  = parsed.get("year_hint") if isinstance(parsed, dict) else getattr(parsed, "year", None)
    
    dup = db.check_duplicate(clean_name, year_hint)
    if dup:
        return jsonify({
            "ok": True, 
            "job_id": dup.get("job_id"), 
            "skipped": [{"movie": movie, "reason": dup["reason"]}]
        })
    # -----------------------

    jid = _uuid.uuid4().hex[:10]
    now = int(time.time())
    with db.conn() as c:
        c.execute(
            "INSERT INTO queue(job_id,movie,site,status,created_at,updated_at) VALUES(?,?,?,?,?,?)",
            (jid, movie, site, "queued", now, now)
        )
    return jsonify({"ok": True, "job_id": jid, "skipped": []})


# ---------------------------------------------------------------------------
# Catalog sync  (consumed by Flutter app — no auth required for zero-rating)
# ---------------------------------------------------------------------------

from ..config import DATA_DIR as _DATA_DIR
@bp.route("/status")
@auth.login_required
def status():
    return jsonify({
        "ok": True,
        "version": "3.0.0",
        "stats": db.count_library(),
        "accounts": len(db.list_accounts()),
        "settings": {
            "media_dir":     str(config.MEDIA_DIR),
            "data_dir":      str(config.DATA_DIR),
            "github_repo":   db.setting("github_repo", ""),
            "github_branch": db.setting("github_branch", "main"),
            "gsheet_id":     db.setting("gsheet_id", ""),
            "gsheet_name":   db.setting("gsheet_name", ""),
        },
    })
