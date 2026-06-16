"""Broadcast Panel — send in-app notifications to all or specific users."""
from __future__ import annotations
import time, logging, os, re
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.broadcast")
bp = Blueprint("broadcast", __name__, url_prefix="/broadcast")

_HTML = """
{% extends "base.html" %}
{% set active="broadcast" %}
{% block title %}Broadcast{% endblock %}
{% block content %}
<style>
.bc-page { max-width: 860px; margin: 0 auto; }
.bc-page h2 { margin: 0 0 4px; }
.bc-sub { color: var(--muted); font-size: .85rem; margin-bottom: 24px; }
.bc-form { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 24px; margin-bottom: 20px; }
.bc-form h3 { margin: 0 0 18px; font-size: 15px; }
.field { margin-bottom: 16px; }
.field label { display: block; font-size: 12px; color: var(--muted); margin-bottom: 6px; text-transform: uppercase; letter-spacing: .5px; }
.field input, .field select, .field textarea { width: 100%; padding: 10px 12px; background: var(--panel2); border: 1px solid var(--border); color: var(--text); border-radius: 8px; font-size: 13px; font-family: inherit; }
.field textarea { min-height: 100px; resize: vertical; }
.field input:focus, .field select:focus, .field textarea:focus { outline: none; border-color: var(--accent); }
.type-row { display: grid; grid-template-columns: repeat(3,1fr); gap: 10px; margin-bottom: 16px; }
.type-card { border: 2px solid var(--border); border-radius: 10px; padding: 12px 14px; cursor: pointer; transition: border-color .15s, background .15s; }
.type-card:hover { border-color: var(--accent); background: var(--panel2); }
.type-card.selected { border-color: var(--accent); background: rgba(124,92,255,.08); }
.type-card input[type=radio] { display: none; }
.type-card .icon { font-size: 1.4rem; margin-bottom: 4px; }
.type-card .name { font-size: 13px; font-weight: 600; }
.type-card .desc { font-size: 11px; color: var(--muted); margin-top: 2px; }
.btn-send { padding: 11px 28px; background: var(--accent); color: #fff; border: none; border-radius: 8px; font-weight: 700; font-size: 14px; cursor: pointer; }
.btn-send:hover { filter: brightness(1.1); }
.history-card { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; }
.history-card h3 { margin: 0; padding: 16px 20px; font-size: 14px; border-bottom: 1px solid var(--border); }
.bc-item { padding: 14px 20px; border-bottom: 1px solid var(--border); }
.bc-item:last-child { border-bottom: none; }
.bc-item-top { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; margin-bottom: 4px; }
.bc-title { font-weight: 600; font-size: 14px; }
.bc-body { font-size: 13px; color: var(--muted); margin-top: 4px; }
.bc-meta { font-size: 11px; color: var(--muted); margin-top: 6px; }
.badge-all  { background: rgba(92,180,255,.15); color: var(--blue); padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 700; }
.badge-paid { background: rgba(0,200,83,.15);   color: var(--ok);   padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 700; }
.badge-free { background: rgba(126,133,155,.15);color: var(--muted);padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 700; }
.badge-exp  { background: rgba(255,193,7,.15);  color: var(--warn); padding: 2px 8px; border-radius: 10px; font-size: 11px; font-weight: 700; }
.empty { text-align: center; color: var(--muted); padding: 30px; font-size: .9rem; }
.success-flash { background: rgba(0,200,83,.1); border: 1px solid rgba(0,200,83,.3); border-radius: 8px; padding: 12px 16px; margin-bottom: 16px; color: var(--ok); font-size: 14px; }
</style>

<div class="bc-page">
  <h2>📢 Broadcast</h2>
  <p class="bc-sub">Send in-app notifications to your users. They see it when they open the app.</p>

  {% if sent %}
  <div class="success-flash">✓ Broadcast sent to {{ sent }} user(s) successfully!</div>
  {% endif %}

  <div class="bc-form">
    <h3>New Broadcast</h3>
    <form method="post" action="/broadcast/send" enctype="multipart/form-data">

      <div class="field">
        <label>Audience</label>
        <div class="type-row">
          <label class="type-card selected" id="card-all">
            <input type="radio" name="audience" value="all" checked onchange="selectCard(this)">
            <div class="icon">👥</div>
            <div class="name">All Users</div>
            <div class="desc">{{ total_users }} users</div>
          </label>
          <label class="type-card" id="card-paid">
            <input type="radio" name="audience" value="paid" onchange="selectCard(this)">
            <div class="icon">💎</div>
            <div class="name">Paid Subscribers</div>
            <div class="desc">{{ active_subs }} subscribers</div>
          </label>
          <label class="type-card" id="card-expiring">
            <input type="radio" name="audience" value="expiring" onchange="selectCard(this)">
            <div class="icon">⚠</div>
            <div class="name">Expiring Soon</div>
            <div class="desc">{{ expiring_7d }} users (≤7 days)</div>
          </label>
        </div>
      </div>

      <div class="field">
        <label>Notification Title</label>
        <input type="text" name="title" placeholder="e.g. New movies added! 🎬" maxlength="80" required>
      </div>

      <div class="field">
        <label>Message Body</label>
        <textarea name="body" placeholder="e.g. Check out the latest additions to RaddFlix — Avatar: Fire and Ash is now available!" maxlength="300" required></textarea>
      </div>

      <div class="field">
        <label>Type / Icon</label>
        <select name="notif_type">
          <option value="info">ℹ Info — general update</option>
          <option value="new_content">🎬 New Content — movie/show added</option>
          <option value="promo">🎁 Promo — discount or offer</option>
          <option value="renewal">⏰ Renewal reminder</option>
          <option value="maintenance">🔧 Maintenance notice</option>
        </select>
      </div>

      <div class="field">
        <label>Image (optional) — served from this server = zero-rated for Jazz users</label>
        <input type="file" name="image" accept="image/*" style="cursor:pointer">
        <div style="font-size:11px;color:var(--muted);margin-top:4px">JPG/PNG/WebP · max 5 MB · shown in the app notification card</div>
      </div>
      <button type="submit" class="btn-send">📢 Send Broadcast</button>
    </form>
  </div>

  <!-- History -->
  <div class="history-card">
    <h3>📋 Broadcast History (Last 20)</h3>
    {% if history %}
      {% for b in history %}
      <div class="bc-item">
        <div class="bc-item-top">
          <span class="bc-title">{{ b.title }}</span>
          {% if b.audience == 'all' %}<span class="badge-all">All Users</span>
          {% elif b.audience == 'paid' %}<span class="badge-paid">Paid</span>
          {% elif b.audience == 'expiring' %}<span class="badge-exp">Expiring</span>
          {% else %}<span class="badge-free">{{ b.audience }}</span>{% endif %}
          <span style="font-size:11px;color:var(--muted);margin-left:auto">{{ b.sent_to }} recipients</span>
        </div>
        {% if b.image_url %}<div style="margin:6px 0"><img src="{{ b.image_url }}" style="max-height:80px;border-radius:8px;object-fit:cover" loading="lazy"></div>{% endif %}
        <div class="bc-body">{{ b.body }}</div>
        <div class="bc-meta">{{ b.sent_human }} · {{ b.notif_type }}</div>
      </div>
      {% endfor %}
    {% else %}
      <div class="empty">No broadcasts sent yet.</div>
    {% endif %}
  </div>
</div>

<script>
function selectCard(radio){
  document.querySelectorAll('.type-card').forEach(c=>c.classList.remove('selected'));
  radio.closest('.type-card').classList.add('selected');
}
</script>
{% endblock %}
"""

def _ensure_tables():
    with db.conn() as c:
        c.execute("""CREATE TABLE IF NOT EXISTS broadcasts (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            audience    TEXT NOT NULL,
            title       TEXT NOT NULL,
            body        TEXT NOT NULL,
            notif_type  TEXT DEFAULT 'info',
            sent_to     INTEGER DEFAULT 0,
            sent_at     INTEGER DEFAULT (strftime('%s','now'))
        )""")
        try:
            cols = [r[1] for r in c.execute("PRAGMA table_info(broadcasts)").fetchall()]
            if "image_path" not in cols:
                c.execute("ALTER TABLE broadcasts ADD COLUMN image_path TEXT")
        except Exception:
            pass
        c.execute("""CREATE TABLE IF NOT EXISTS user_notifications (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id     INTEGER NOT NULL,
            broadcast_id INTEGER REFERENCES broadcasts(id),
            title       TEXT NOT NULL,
            body        TEXT NOT NULL,
            notif_type  TEXT DEFAULT 'info',
            is_read     INTEGER DEFAULT 0,
            created_at  INTEGER DEFAULT (strftime('%s','now'))
        )""")


def _fmt(ts):
    import datetime as dt
    if not ts: return "—"
    return dt.datetime.fromtimestamp(int(ts)).strftime("%d %b %Y, %H:%M")


@bp.route("/")
@login_required
def index():
    _ensure_tables()
    now = int(time.time())
    sent = request.args.get("sent")

    with db.conn() as c:
        total_users  = c.execute("SELECT COUNT(*) AS n FROM app_users").fetchone()["n"]
        active_subs  = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at > ?", (now,)).fetchone()["n"]
        expiring_7d  = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at BETWEEN ? AND ?", (now, now+7*86400)).fetchone()["n"]
        hist_rows    = c.execute("SELECT * FROM broadcasts ORDER BY sent_at DESC LIMIT 20").fetchall()

    history = []
    for r in hist_rows:
        d = dict(r)
        d["sent_human"] = _fmt(r["sent_at"])
        keys = r.keys() if hasattr(r, "keys") else []
        if "image_path" in keys and r["image_path"]:
            d["image_url"] = f"/api/notifications/image/{r['id']}"
        else:
            d["image_url"] = None
        history.append(d)

    return render_template_string(_HTML,
        total_users=total_users, active_subs=active_subs,
        expiring_7d=expiring_7d, history=history, sent=sent)


@bp.route("/send", methods=["POST"])
@login_required
def send():
    _ensure_tables()
    audience   = request.form.get("audience", "all")
    title      = request.form.get("title", "").strip()
    body       = request.form.get("body", "").strip()
    notif_type = request.form.get("notif_type", "info")
    now        = int(time.time())

    # Handle image upload
    image_path = None
    img_file = request.files.get("image")
    if img_file and img_file.filename:
        ext = os.path.splitext(img_file.filename)[1].lower()
        if ext not in (".jpg", ".jpeg", ".png", ".webp", ".gif"):
            ext = ".jpg"
        images_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                  "..", "data", "notif_images")
        os.makedirs(images_dir, exist_ok=True)
        tmp_path = os.path.join(images_dir, f"tmp_{now}{ext}")
        img_file.save(tmp_path)
        image_path = tmp_path

    if not title or not body:
        return redirect(url_for("broadcast.index"))

    with db.conn() as c:
        if audience == "all":
            users = c.execute("SELECT id FROM app_users").fetchall()
        elif audience == "paid":
            users = c.execute("""
                SELECT DISTINCT u.id FROM app_users u
                JOIN app_subscriptions s ON s.user_id=u.id
                WHERE s.is_active=1 AND s.expires_at > ?
            """, (now,)).fetchall()
        elif audience == "expiring":
            users = c.execute("""
                SELECT DISTINCT u.id FROM app_users u
                JOIN app_subscriptions s ON s.user_id=u.id
                WHERE s.is_active=1 AND s.expires_at BETWEEN ? AND ?
            """, (now, now + 7*86400)).fetchall()
        else:
            users = []

        bc_id = c.execute(
            "INSERT INTO broadcasts(audience,title,body,notif_type,sent_to,sent_at,image_path) VALUES(?,?,?,?,?,?,?)",
            (audience, title, body, notif_type, len(users), now, None)
        ).lastrowid
        # Rename temp image to final name with broadcast id
        if image_path and os.path.exists(image_path):
            ext = os.path.splitext(image_path)[1]
            final = os.path.join(os.path.dirname(image_path), f"bc_{bc_id}{ext}")
            os.rename(image_path, final)
            rel = os.path.relpath(final, "/opt/jazzmax")
            c.execute("UPDATE broadcasts SET image_path=? WHERE id=?", (rel, bc_id))

        for u in users:
            c.execute(
                "INSERT INTO user_notifications(user_id,broadcast_id,title,body,notif_type,created_at) VALUES(?,?,?,?,?,?)",
                (u["id"], bc_id, title, body, notif_type, now)
            )

    log.info("Broadcast sent: audience=%s title=%s recipients=%d", audience, title, len(users))
    return redirect(url_for("broadcast.index", sent=len(users)))


@bp.route("/api/user/<int:user_id>")
def user_notifications(user_id: int):
    """Flutter app polls this to get unread notifications."""
    _ensure_tables()
    with db.conn() as c:
        rows = c.execute("""
            SELECT id, title, body, notif_type, is_read, created_at
            FROM user_notifications WHERE user_id=? ORDER BY created_at DESC LIMIT 20
        """, (user_id,)).fetchall()
    return jsonify({"notifications": [dict(r) for r in rows]})


@bp.route("/api/user/<int:user_id>/<int:notif_id>/read", methods=["POST"])
def mark_read(user_id: int, notif_id: int):
    _ensure_tables()
    with db.conn() as c:
        c.execute("UPDATE user_notifications SET is_read=1 WHERE id=? AND user_id=?", (notif_id, user_id))
    return jsonify({"ok": True})
