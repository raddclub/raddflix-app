"""Zero-Rating / JazzDrive DB Update admin panel."""
from __future__ import annotations
import os, json, time, datetime, logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify, send_file
from hub import db
from hub.config import DATA_DIR as _DATA_DIR
from hub.auth import login_required

log = logging.getLogger("hub.zero_rating")
bp = Blueprint("zero_rating", __name__, url_prefix="/zero-rating")

_DB_UPDATE_PATH = str(_DATA_DIR / "db_update.json")


def _get_db_update_info():
    try:
        data = json.load(open(_DB_UPDATE_PATH))
        gen_ts = data.get("generated_at", "")
        return True, len(data.get("titles", [])), len(data.get("episodes", [])), gen_ts, os.path.getsize(_DB_UPDATE_PATH) // 1024
    except Exception:
        return False, 0, 0, None, 0


_HTML = """
{% extends "base.html" %}
{% set active="zero_rating" %}
{% block title %}Zero-Rating{% endblock %}
{% block content %}
<style>
.zr-page { max-width: 960px; margin: 0 auto; }
.zr-page h2 { margin: 0 0 4px; }
.zr-sub { color: var(--muted); font-size: .85rem; margin-bottom: 24px; }
.status-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 14px; margin-bottom: 24px; }
@media(max-width:700px){ .status-grid { grid-template-columns: repeat(2,1fr); } }
.s-tile { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 16px 18px; }
.s-tile .k { font-size: .75rem; text-transform: uppercase; letter-spacing: .5px; color: var(--muted); }
.s-tile .v { font-size: 1.6rem; font-weight: 700; margin-top: 4px; word-break: break-all; }
.card { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 22px; margin-bottom: 18px; }
.card h3 { margin: 0 0 16px; font-size: 14px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
.card-accent { border-color: var(--accent); }
.action-row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
.btn-prim  { padding: 10px 22px; background: var(--accent); color: #fff; border: none; border-radius: 8px; font-weight: 700; font-size: 14px; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }
.btn-prim:hover { filter: brightness(1.1); color: #fff; }
.btn-sec   { padding: 10px 18px; background: var(--panel2); color: var(--text); border: 1px solid var(--border); border-radius: 8px; font-size: 13px; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }
.btn-sec:hover { border-color: var(--accent); }
.btn-green { background: rgba(0,200,83,.15); color: var(--ok); border: 1px solid rgba(0,200,83,.3); border-radius: 8px; padding: 10px 18px; font-size: 13px; font-weight: 600; cursor: pointer; text-decoration: none; display: inline-flex; align-items: center; gap: 6px; }
.ok-badge  { display: inline-flex; align-items: center; gap: 5px; padding: 4px 10px; border-radius: 10px; font-size: 12px; font-weight: 700; }
.ok-badge.green  { background: rgba(0,200,83,.15); color: var(--ok); }
.ok-badge.red    { background: rgba(255,107,107,.1); color: var(--err); }
.flash-ok  { background: rgba(0,200,83,.1); border: 1px solid rgba(0,200,83,.3); border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; color: var(--ok); font-size: 14px; }
.flash-err { background: rgba(255,107,107,.08); border: 1px solid rgba(255,107,107,.3); border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; color: var(--err); font-size: 14px; }
</style>

<div class="zr-page">
  <h2>⚡ Zero-Rating Manager</h2>
  <p class="zr-sub">Jazz SIM users stream and browse catalog without a data bundle. Catalog sync is served directly from Oracle.</p>

  {% if msg %}
  <div class="flash-ok">{{ msg }}</div>
  {% endif %}
  {% if err %}
  <div class="flash-err">{{ err }}</div>
  {% endif %}

  <!-- ── STATUS TILES ───────────────────────────────────────────────── -->
  <div class="status-grid">
    <div class="s-tile">
      <div class="k">Published Titles</div>
      <div class="v" style="color:var(--ok)">{{ published_titles }}</div>
    </div>
    <div class="s-tile">
      <div class="k">db_update.json</div>
      <div class="v" style="font-size:1.1rem">
        {% if db_update_exists %}
          <span class="ok-badge green">✓ Ready</span>
        {% else %}
          <span class="ok-badge red">✗ Missing</span>
        {% endif %}
      </div>
    </div>
    <div class="s-tile">
      <div class="k">Titles in Export</div>
      <div class="v" style="color:var(--ok)">{{ json_titles }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Generated</div>
      <div class="v" style="font-size:.85rem;color:var(--muted)">{{ db_update_generated_at or '—' }}</div>
    </div>
  </div>

  <!-- ── FREE/PAID TITLES ───────────────────────────────────────────────── -->
  <div class="card">
    <h3>🔓 Free vs Paid Titles ({{ published_titles }} published)</h3>
    <p style="font-size:13px;color:var(--muted);margin:0 0 14px">
      Free titles are visible to guest users without a subscription.
    </p>
    <div style="overflow-x:auto">
    <table style="width:100%;border-collapse:collapse">
      <thead><tr>
        <th style="text-align:left;padding:8px 12px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Title</th>
        <th style="text-align:center;padding:8px 12px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Free?</th>
        <th style="padding:8px 12px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Toggle</th>
      </tr></thead>
      <tbody>
      {% for t in titles %}
      <tr>
        <td style="padding:8px 12px;font-size:13px">{{ t.title }} <span style="color:var(--muted);font-size:11px">({{ t.year }})</span></td>
        <td style="text-align:center;padding:8px 12px">
          {% if t.is_free %}
            <span style="padding:2px 10px;border-radius:10px;font-size:12px;font-weight:700;background:rgba(0,200,83,.15);color:var(--ok)">FREE</span>
          {% else %}
            <span style="padding:2px 10px;border-radius:10px;font-size:12px;font-weight:700;background:rgba(126,133,155,.15);color:var(--muted)">PAID</span>
          {% endif %}
        </td>
        <td style="padding:8px 12px">
          <form method="post" action="/zero-rating/toggle-free/{{ t.id }}" style="display:inline">
            <button type="submit" style="padding:3px 12px;font-size:12px;border-radius:6px;border:1px solid var(--border);background:var(--panel2);color:var(--text);cursor:pointer">
              {% if t.is_free %}Make Paid{% else %}Make Free{% endif %}
            </button>
          </form>
        </td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
    </div>
  </div>

  <!-- ── CATALOG EXPORT ───────────────────────────────────── -->
  <div class="card card-accent">
    <h3>🗄 Catalog Export — db_update.json</h3>
    <p style="font-size:13px;color:var(--muted);margin:0 0 14px">
      Full catalog export for Oracle sync. Contains all published titles with metadata.
    </p>
    <div style="margin-bottom:10px;font-size:12px;color:var(--muted)">
      {{ 'Generated: ' + db_update_generated_at if db_update_exists else 'Not generated yet' }}
      {{ ' · ' + db_update_size_kb|string + ' KB · ' + json_titles|string + ' titles · ' + json_episodes|string + ' episodes' if db_update_exists else '' }}
    </div>
    <div class="action-row">
      <form method="post" action="/zero-rating/generate">
        <button type="submit" class="btn-prim">⚡ Generate db_update.json</button>
      </form>
      {% if db_update_exists %}
      <a href="/zero-rating/download" class="btn-green">⬇ Download</a>
      {% endif %}
    </div>
  </div>
</div>
{% endblock %}
"""


def _infer_status(row) -> str:
    def _get(r, k, default=None):
        try: return r[k]
        except (IndexError, KeyError): return default
    if _get(row, "status"):
        return _get(row, "status")
    if _get(row, "is_ongoing"):
        return "ongoing"
    mt = (_get(row, "media_type") or "movie").lower()
    if mt == "movie":
        return "released"
    try:
        yr = int(_get(row, "year") or 0)
        if yr >= 2025:
            return "ongoing"
        return "completed"
    except Exception:
        return "released"


def _render_index(msg=None, err=None):
    db_exists, json_titles, json_episodes, db_gen_at, db_size = _get_db_update_info()

    with db.conn() as c:
        published = c.execute("SELECT COUNT(*) AS n FROM titles WHERE is_published=1").fetchone()["n"]
        titles = c.execute("SELECT id, title, year, is_free FROM titles WHERE is_published=1 ORDER BY title").fetchall()

    return render_template_string(_HTML,
        msg=msg, err=err,
        db_update_exists=db_exists,
        json_titles=json_titles,
        json_episodes=json_episodes,
        db_update_generated_at=db_gen_at,
        db_update_size_kb=db_size,
        published_titles=published,
        titles=[dict(t) for t in titles],
    )


@bp.route("/")
@login_required
def index():
    msg = request.args.get("msg")
    return _render_index(msg=msg)


@bp.route("/clear-db-update-url", methods=["POST"])
@login_required
def clear_db_update_url():
    with db.conn() as c:
        c.execute("DELETE FROM settings WHERE k='jd_db_update_url'")
    return _render_index(msg="✓ Old full-catalog JazzDrive URL cleared.")


@bp.route("/generate", methods=["POST"])
@login_required
def generate():
    with db.conn() as c:
        title_rows = c.execute("""
            SELECT t.id, t.title, t.year, t.media_type, t.plot,
                   t.rating, t.genres, t.language, t.is_free, t.updated_at,
                   t.poster, t.poster_share_url, t.runtime, t.season_count, t.episode_count,
                   t.status, t.is_ongoing,
                   f.id AS file_id
            FROM titles t
            LEFT JOIN files f ON f.title_id = t.id
              AND (f.season IS NULL OR f.season = 0)
            WHERE t.is_published = 1
            GROUP BY t.id ORDER BY t.id
        """).fetchall()

    title_ids = [r["id"] for r in title_rows]
    titles_out = []
    for r in title_rows:
        genres = []
        try:
            genres = json.loads(r["genres"] or "[]")
            if not isinstance(genres, list): genres = [str(genres)]
        except Exception:
            pass
        titles_out.append({
            "id": r["id"], "title": r["title"] or "",
            "year": r["year"], "media_type": r["media_type"] or "movie",
            "description": r["plot"] or "",
            "rating": float(r["rating"] or 0), "genres": genres,
            "language": r["language"] or "",
            "is_free": 1 if r["is_free"] else 0,
            "runtime": r["runtime"],
            "season_count": r["season_count"],
            "episode_count": r["episode_count"],
            "poster_url": r["poster"] or "",
            "poster_share_url": r["poster_share_url"] or "",
            "db_version": int(r["updated_at"] or 0),
            "file_id": str(r["file_id"]) if r["file_id"] else None,
            "status": r["status"] or _infer_status(r),
            "is_ongoing": 1 if (r["is_ongoing"] or (r["status"] or "").lower() == "ongoing") else 0,
        })

    episodes_out = []
    if title_ids:
        ph = ",".join("?" * len(title_ids))
        with db.conn() as c:
            ep_rows = c.execute(f"""
                SELECT id, title_id, season, episode
                FROM files
                WHERE title_id IN ({ph})
                  AND season IS NOT NULL AND season > 0
                ORDER BY title_id, season, episode
            """, title_ids).fetchall()
        for r in ep_rows:
            episodes_out.append({
                "id": r["id"], "title_id": r["title_id"],
                "file_id": str(r["id"]),
                "season": r["season"], "episode": r["episode"],
                "label": "S{:02d}E{:02d}".format(r["season"] or 0, r["episode"] or 0),
                "quality": None, "is_free": 0,
            })

    now = int(time.time())
    payload = {
        "version": now,
        "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "titles": titles_out, "episodes": episodes_out,
    }
    with open(_DB_UPDATE_PATH, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    log.info("Generated db_update.json: %d titles, %d episodes", len(titles_out), len(episodes_out))
    return _render_index(msg=f"✓ Generated db_update.json — {len(titles_out)} titles, {len(episodes_out)} episodes")


@bp.route("/download")
@login_required
def download():
    if not os.path.exists(_DB_UPDATE_PATH):
        return "db_update.json not found — generate it first", 404
    return send_file(_DB_UPDATE_PATH, as_attachment=True, download_name="db_update.json", mimetype="application/json")


@bp.route("/set-url", methods=["POST"])
@login_required
def set_url():
    url = request.form.get("url", "").strip()
    if not url:
        return redirect(url_for("zero_rating.index"))
    with db.conn() as c:
        c.execute("INSERT OR REPLACE INTO settings(k,v) VALUES('jd_db_update_url',?)", (url,))
    return _render_index(msg=f"✓ JD full-catalog URL saved: {url}")


@bp.route("/toggle-free/<int:title_id>", methods=["POST"])
@login_required
def toggle_free(title_id: int):
    with db.conn() as c:
        row = c.execute("SELECT is_free FROM titles WHERE id=?", (title_id,)).fetchone()
        if row:
            new_val = 0 if row["is_free"] else 1
            c.execute("UPDATE titles SET is_free=? WHERE id=?", (new_val, title_id))
    return _render_index(msg="✓ Title updated")
