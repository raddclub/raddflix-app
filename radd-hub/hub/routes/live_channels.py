"""Live TV Channels — Admin panel + mobile API.

Admin:
  GET  /live/                      — channel list + management table
  POST /live/<channel_id>/toggle   — toggle is_active
  POST /live/<channel_id>/free     — toggle is_free
  POST /live/<channel_id>/featured — set as featured (clears previous)
  POST /live/<channel_id>/sort     — update sort_order
  POST /live/<channel_id>/edit     — update stream_url / logo_url / notes

Mobile API:
  GET  /api/live/channels          — channel list for the Flutter app
"""
from __future__ import annotations
import time
import logging
from flask import Blueprint, request, redirect, url_for, jsonify, render_template_string
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.live_channels")

bp       = Blueprint("live_channels", __name__, url_prefix="/live")
bp_mobile = Blueprint("live_channels_api", __name__)

# ── Category meta ─────────────────────────────────────────────────────────────
_CATS = [
    ("all",           "All",        "📺"),
    ("sports",        "Sports",     "🏏"),
    ("religious",     "Islamic",    "🕌"),
    ("news",          "News",       "📰"),
    ("entertainment", "Drama",      "🎭"),
    ("kids",          "Kids",       "🧸"),
    ("movies",        "Movies",     "🎬"),
    ("docs",          "Lifestyle",  "🌿"),
]
_CAT_COLORS = {
    "sports":        "#FF6B35",
    "religious":     "#00BFA5",
    "news":          "#42A5F5",
    "entertainment": "#AB47BC",
    "kids":          "#FFCA28",
    "movies":        "#FF7043",
    "docs":          "#66BB6A",
}

# ── Helpers ───────────────────────────────────────────────────────────────────

def _conn():
    return db._conn()

def _lock():
    return db._lock

def _all_channels(cat: str = "all", include_inactive: bool = True):
    q = "SELECT * FROM live_channels"
    params: list = []
    clauses: list[str] = []
    if cat != "all":
        clauses.append("category = ?")
        params.append(cat)
    if not include_inactive:
        clauses.append("is_active = 1")
    if clauses:
        q += " WHERE " + " AND ".join(clauses)
    q += " ORDER BY sort_order ASC, name ASC"
    with db._lock, db._conn() as c:
        return c.execute(q, params).fetchall()

def _get_channel(channel_id: str):
    with db._lock, db._conn() as c:
        return c.execute("SELECT * FROM live_channels WHERE channel_id = ?",
                         (channel_id,)).fetchone()

def _stats():
    with db._lock, db._conn() as c:
        total    = c.execute("SELECT COUNT(*) AS n FROM live_channels").fetchone()["n"]
        active   = c.execute("SELECT COUNT(*) AS n FROM live_channels WHERE is_active=1").fetchone()["n"]
        free     = c.execute("SELECT COUNT(*) AS n FROM live_channels WHERE is_free=1 AND is_active=1").fetchone()["n"]
        featured = c.execute("SELECT channel_id, name FROM live_channels WHERE is_featured=1").fetchone()
    return total, active, free, featured

# ── Admin HTML ────────────────────────────────────────────────────────────────

_PAGE = """
{% extends 'base.html' %}
{% set active = 'live_channels' %}
{% block content %}
<style>
.lc-page{max-width:1400px;margin:0 auto}
.lc-page h2{margin:0 0 4px}
.sub-sub{color:var(--muted);font-size:.85rem;margin-bottom:22px}
.stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:24px}
@media(max-width:700px){.stat-grid{grid-template-columns:repeat(2,1fr)}}
.s-tile{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:16px 18px}
.s-tile .k{font-size:.75rem;text-transform:uppercase;letter-spacing:.5px;color:var(--muted)}
.s-tile .v{font-size:2rem;font-weight:700;margin-top:4px}
.cat-tabs{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:18px}
.cat-tab{padding:5px 14px;border-radius:20px;border:1px solid var(--border);background:var(--panel);
         color:var(--muted);font-size:12px;font-weight:600;text-decoration:none;transition:all .15s}
.cat-tab:hover{border-color:var(--accent);color:var(--accent)}
.cat-tab.active{background:var(--accent);border-color:var(--accent);color:#fff}
.lc-table{width:100%;border-collapse:collapse;font-size:13px}
.lc-table th{padding:8px 10px;text-align:left;color:var(--muted);font-size:11px;
             text-transform:uppercase;letter-spacing:.5px;border-bottom:1px solid var(--border)}
.lc-table td{padding:8px 10px;border-bottom:1px solid var(--border);vertical-align:middle}
.lc-table tr:hover td{background:var(--panel2)}
.lc-table tr.inactive td{opacity:.45}
.logo-thumb{width:36px;height:36px;object-fit:contain;border-radius:6px;background:var(--panel2)}
.badge-cat{display:inline-block;padding:2px 8px;border-radius:10px;font-size:10px;font-weight:700}
.btn-xs{display:inline-block;padding:3px 10px;border-radius:6px;font-size:11px;font-weight:600;
        border:none;cursor:pointer;text-align:center;min-width:52px}
.btn-on {background:rgba(92,214,111,.15);color:#4CAF50;border:1px solid rgba(92,214,111,.3)}
.btn-off{background:rgba(255,107,107,.10);color:#f44336;border:1px solid rgba(255,107,107,.25)}
.btn-accent{background:rgba(124,92,255,.12);color:#7c5cff;border:1px solid rgba(124,92,255,.3)}
.btn-star{background:rgba(255,202,40,.12);color:#FFC107;border:1px solid rgba(255,202,40,.3)}
.btn-star.active-star{background:#FFC107;color:#000}
.url-input{background:transparent;border:none;color:var(--text);font-size:12px;width:100%;
           outline:none;font-family:monospace}
.url-input:focus{background:var(--panel2);border-radius:4px;padding:2px 4px}
.edit-form{display:inline}
.sort-input{width:48px;background:var(--panel2);border:1px solid var(--border);
            border-radius:5px;color:var(--text);text-align:center;padding:2px 4px;font-size:12px}
</style>

<div class="lc-page">
  <h2>📺 Live TV Channels</h2>
  <p class="sub-sub">Manage the live channel catalogue. Changes take effect immediately — the app reads <code>/api/live/channels</code> on every tab open.</p>

  <!-- Stats -->
  <div class="stat-grid">
    <div class="s-tile"><div class="k">Total</div><div class="v">{{ total }}</div></div>
    <div class="s-tile"><div class="k">Active</div><div class="v" style="color:var(--ok)">{{ active }}</div></div>
    <div class="s-tile"><div class="k">Free</div><div class="v" style="color:var(--accent)">{{ free }}</div></div>
    <div class="s-tile"><div class="k">Featured</div>
      <div class="v" style="font-size:1rem;padding-top:6px;color:#FFC107">
        {% if featured %}{{ featured['name'] }}{% else %}—{% endif %}
      </div>
    </div>
  </div>

  <!-- Category tabs -->
  <div class="cat-tabs">
    {% for cid, clabel, cicon in cats %}
    <a href="/live/?cat={{ cid }}" class="cat-tab {{ 'active' if cat==cid }}">{{ cicon }} {{ clabel }}</a>
    {% endfor %}
  </div>

  <!-- Channel table -->
  <div style="overflow-x:auto">
  <table class="lc-table">
    <thead>
      <tr>
        <th style="width:40px">#</th>
        <th style="width:40px"></th>
        <th>Channel</th>
        <th>Category</th>
        <th>Stream URL</th>
        <th style="width:60px">Free</th>
        <th style="width:70px">Active</th>
        <th style="width:60px">Featured</th>
        <th style="width:55px">Sort</th>
      </tr>
    </thead>
    <tbody>
    {% for ch in channels %}
    <tr class="{{ '' if ch['is_active'] else 'inactive' }}">
      <td style="color:var(--muted);font-size:11px">{{ ch['sort_order'] }}</td>
      <td>
        <img src="{{ ch['logo_url'] }}" class="logo-thumb" onerror="this.style.display='none'">
      </td>
      <td>
        <div style="font-weight:600">{{ ch['name'] }}</div>
        <div style="color:var(--muted);font-size:10px">{{ ch['channel_id'] }}</div>
      </td>
      <td>
        <span class="badge-cat" style="background:{{ cat_colors.get(ch['category'],'#888') }}22;
              color:{{ cat_colors.get(ch['category'],'#888') }}">
          {{ ch['genre_label'] }}
        </span>
      </td>
      <td style="max-width:280px">
        <form class="edit-form" method="post" action="/live/{{ ch['channel_id'] }}/edit">
          <input class="url-input" name="stream_url" value="{{ ch['stream_url'] }}"
                 title="Edit and press Enter to save" onkeydown="if(event.key==='Enter'){this.form.submit()}">
          <input type="hidden" name="logo_url" value="{{ ch['logo_url'] }}">
          <input type="hidden" name="notes" value="{{ ch['notes'] or '' }}">
        </form>
      </td>
      <td>
        <form method="post" action="/live/{{ ch['channel_id'] }}/free">
          <button class="btn-xs {{ 'btn-on' if ch['is_free'] else 'btn-off' }}">
            {{ 'FREE' if ch['is_free'] else 'PAID' }}
          </button>
        </form>
      </td>
      <td>
        <form method="post" action="/live/{{ ch['channel_id'] }}/toggle">
          <button class="btn-xs {{ 'btn-on' if ch['is_active'] else 'btn-off' }}">
            {{ 'ON' if ch['is_active'] else 'OFF' }}
          </button>
        </form>
      </td>
      <td>
        <form method="post" action="/live/{{ ch['channel_id'] }}/featured">
          <button class="btn-xs btn-star {{ 'active-star' if ch['is_featured'] }}"
                  title="Set as auto-loaded featured channel">
            ★
          </button>
        </form>
      </td>
      <td>
        <form method="post" action="/live/{{ ch['channel_id'] }}/sort">
          <input class="sort-input" name="sort_order" value="{{ ch['sort_order'] }}"
                 onchange="this.form.submit()">
        </form>
      </td>
    </tr>
    {% endfor %}
    </tbody>
  </table>
  </div>
</div>
{% endblock %}
"""

# ── Admin routes ──────────────────────────────────────────────────────────────

@bp.route("/", methods=["GET"])
@login_required
def index():
    cat = request.args.get("cat", "all")
    channels = _all_channels(cat, include_inactive=True)
    total, active, free, featured = _stats()
    return render_template_string(
        _PAGE,
        channels=channels,
        cat=cat,
        cats=_CATS,
        cat_colors=_CAT_COLORS,
        total=total,
        active=active,
        free=free,
        featured=featured,
    )


@bp.route("/<channel_id>/toggle", methods=["POST"])
@login_required
def toggle_active(channel_id: str):
    ch = _get_channel(channel_id)
    if not ch:
        return jsonify(ok=False, error="not found"), 404
    new_val = 0 if ch["is_active"] else 1
    with db._lock, db._conn() as c:
        c.execute(
            "UPDATE live_channels SET is_active=?, updated_at=? WHERE channel_id=?",
            (new_val, int(time.time()), channel_id),
        )
    cat = request.args.get("cat", "all")
    return redirect(url_for("live_channels.index", cat=cat))


@bp.route("/<channel_id>/free", methods=["POST"])
@login_required
def toggle_free(channel_id: str):
    ch = _get_channel(channel_id)
    if not ch:
        return jsonify(ok=False, error="not found"), 404
    new_val = 0 if ch["is_free"] else 1
    with db._lock, db._conn() as c:
        c.execute(
            "UPDATE live_channels SET is_free=?, updated_at=? WHERE channel_id=?",
            (new_val, int(time.time()), channel_id),
        )
    cat = request.args.get("cat", "all")
    return redirect(url_for("live_channels.index", cat=cat))


@bp.route("/<channel_id>/featured", methods=["POST"])
@login_required
def set_featured(channel_id: str):
    """Clears any existing featured channel, then marks this one."""
    with db._lock, db._conn() as c:
        c.execute("UPDATE live_channels SET is_featured=0, updated_at=?",
                  (int(time.time()),))
        c.execute(
            "UPDATE live_channels SET is_featured=1, updated_at=? WHERE channel_id=?",
            (int(time.time()), channel_id),
        )
    cat = request.args.get("cat", "all")
    return redirect(url_for("live_channels.index", cat=cat))


@bp.route("/<channel_id>/sort", methods=["POST"])
@login_required
def update_sort(channel_id: str):
    try:
        order = int(request.form.get("sort_order", 999))
    except ValueError:
        order = 999
    with db._lock, db._conn() as c:
        c.execute(
            "UPDATE live_channels SET sort_order=?, updated_at=? WHERE channel_id=?",
            (order, int(time.time()), channel_id),
        )
    cat = request.args.get("cat", "all")
    return redirect(url_for("live_channels.index", cat=cat))


@bp.route("/<channel_id>/edit", methods=["POST"])
@login_required
def edit_channel(channel_id: str):
    stream_url = request.form.get("stream_url", "").strip()
    logo_url   = request.form.get("logo_url", "").strip()
    notes      = request.form.get("notes", "").strip()
    with db._lock, db._conn() as c:
        c.execute(
            """UPDATE live_channels
               SET stream_url=?, logo_url=?, notes=?, updated_at=?
               WHERE channel_id=?""",
            (stream_url, logo_url, notes, int(time.time()), channel_id),
        )
    cat = request.args.get("cat", "all")
    return redirect(url_for("live_channels.index", cat=cat))


# ── Mobile API ────────────────────────────────────────────────────────────────

@bp_mobile.route("/api/live/channels", methods=["GET"])
def api_channels():
    """Returns active channels for the Flutter app.

    Query params:
      cat (str)  — filter by category ('all' or omit for all)
    """
    cat = request.args.get("cat", "all")
    rows = _all_channels(cat, include_inactive=False)
    channels = []
    for r in rows:
        channels.append({
            "channel_id":    r["channel_id"],
            "name":          r["name"],
            "category":      r["category"],
            "genre_label":   r["genre_label"],
            "logo_url":      r["logo_url"],
            "local_asset":   r["local_asset"],
            "stream_url":    r["stream_url"],
            "backdrop_color": r["backdrop_color"],
            "is_free":       bool(r["is_free"]),
            "is_featured":   bool(r["is_featured"]),
            "sort_order":    r["sort_order"],
            "updated_at":    r["updated_at"],
        })
    cats = [c[0] for c in _CATS if c[0] != "all"]
    return jsonify(
        ok=True,
        channels=channels,
        total=len(channels),
        categories=["all"] + cats,
        server_ts=int(time.time()),
    )
