"""App Users Management Panel — admin UI in Radd Hub.

Routes:
  GET  /app-users/                    — list all users with subscriptions
  POST /app-users/<id>/set-plan       — manually set subscription plan
  POST /app-users/<id>/toggle-active  — activate / deactivate user account
  POST /app-users/<id>/toggle-admin   — grant / revoke admin flag
  POST /app-users/grant-admin         — grant admin by phone number
  POST /app-users/<id>/delete         — delete user account
  GET  /app-users/<id>/history        — watch history for a user (JSON)
"""
from __future__ import annotations
import time
import logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.app_users_panel")

bp = Blueprint("app_users_panel", __name__, url_prefix="/app-users")

PLAN_DURATIONS = {
    "free":     0,
    "basic":    30,
    "standard": 30,
    "premium":  30,
}

_HTML = """
{% extends "base.html" %}
{% block title %}App Users{% endblock %}
{% block content %}
<style>
.up-page { max-width: 1100px; margin: 0 auto; padding: 20px 16px; }
.up-page h1 { font-size: 1.4rem; margin-bottom: 4px; color: var(--text); }
.up-page .sub { color: var(--muted); font-size: .85rem; margin-bottom: 24px; }

/* ── Stat tiles ─────────────────── */
.stats-row { display: grid; grid-template-columns: repeat(5,1fr); gap: 12px; margin-bottom: 24px; }
@media(max-width:800px){ .stats-row { grid-template-columns: repeat(3,1fr); } }
@media(max-width:500px){ .stats-row { grid-template-columns: repeat(2,1fr); } }
.stat-tile {
  background: var(--panel2); border: 1px solid var(--border); border-radius: 12px;
  padding: 14px 16px;
}
.stat-tile .k { font-size: .75rem; text-transform: uppercase; letter-spacing: .5px; color: var(--muted); }
.stat-tile .v { font-size: 1.8rem; font-weight: 700; margin-top: 4px; }
.stat-tile .v.green  { color: var(--ok); }
.stat-tile .v.blue   { color: var(--blue); }
.stat-tile .v.warn   { color: var(--warn); }
.stat-tile .v.red    { color: var(--err); }
.stat-tile .v.purple { color: #a78bfa; }

/* ── Admin management box ───────── */
.admin-box {
  background: var(--panel2); border: 1px solid rgba(167,139,250,.35);
  border-radius: 14px; padding: 18px 20px; margin-bottom: 24px;
}
.admin-box h2 {
  font-size: 1rem; font-weight: 700; color: #a78bfa; margin: 0 0 14px;
  display: flex; align-items: center; gap: 8px;
}
.admin-list { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 14px; }
.admin-chip {
  display: flex; align-items: center; gap: 7px;
  background: rgba(167,139,250,.12); border: 1px solid rgba(167,139,250,.3);
  border-radius: 20px; padding: 5px 10px 5px 12px; font-size: .83rem;
}
.admin-chip .num  { font-family: monospace; color: var(--text); font-weight: 600; }
.admin-chip .uid  { color: var(--muted); font-size: .72rem; }
.admin-chip form  { margin: 0; }
.admin-chip .revoke-btn {
  background: none; border: none; color: var(--err); cursor: pointer;
  font-size: .85rem; padding: 0 2px; line-height: 1;
  opacity: .7; transition: opacity .12s;
}
.admin-chip .revoke-btn:hover { opacity: 1; }
.admin-none { color: var(--muted); font-size: .85rem; font-style: italic; margin-bottom: 14px; }

.grant-row { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
.grant-input {
  flex: 1; min-width: 180px; max-width: 300px;
  padding: 7px 12px; background: var(--panel); border: 1px solid var(--border);
  border-radius: 8px; color: var(--text); font-size: .88rem; font-family: monospace;
}
.grant-input::placeholder { color: var(--muted); font-family: sans-serif; }
.btn-grant {
  padding: 7px 18px; background: #7c3aed; color: #fff; border: none;
  border-radius: 8px; font-size: .85rem; font-weight: 600; cursor: pointer;
  transition: background .12s;
}
.btn-grant:hover { background: #6d28d9; }
.flash-msg {
  padding: 8px 14px; border-radius: 8px; font-size: .83rem; margin-top: 10px;
  display: none;
}
.flash-msg.ok  { background: rgba(92,214,111,.12); color: var(--ok); border: 1px solid rgba(92,214,111,.3); }
.flash-msg.err { background: rgba(255,107,107,.12); color: var(--err); border: 1px solid rgba(255,107,107,.3); }

/* ── Filters ────────────────────── */
.filters { display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; align-items: center; }
.f-btn {
  padding: 5px 14px; border-radius: 20px; border: 1px solid var(--border);
  background: var(--panel2); color: var(--muted); cursor: pointer; font-size: .82rem;
  text-decoration: none; transition: background .12s;
}
.f-btn.active, .f-btn:hover { background: var(--accent); color: #fff; border-color: var(--accent); }
.f-btn.admin-btn.active, .f-btn.admin-btn:hover { background: #7c3aed; border-color: #7c3aed; }
.search-box {
  margin-left: auto; padding: 6px 12px; background: var(--panel2);
  border: 1px solid var(--border); border-radius: 8px; color: var(--text);
  font-size: .85rem; width: 200px;
}

/* ── User cards ─────────────────── */
.user-card {
  background: var(--panel); border: 1px solid var(--border); border-radius: 12px;
  padding: 16px 18px; margin-bottom: 10px; display: grid;
  grid-template-columns: auto 1fr auto; gap: 14px; align-items: start;
}
.user-card.inactive { opacity: .6; }
.user-card.is-admin { border-color: rgba(167,139,250,.4); }
.user-avatar {
  width: 40px; height: 40px; border-radius: 50%; background: var(--panel2);
  border: 2px solid var(--border); display: flex; align-items: center;
  justify-content: center; font-size: 1rem; font-weight: 700; color: var(--accent);
  flex-shrink: 0;
}
.user-card.is-admin .user-avatar { border-color: #a78bfa; color: #a78bfa; }
.user-info .name { font-weight: 600; color: var(--text); font-size: .95rem; }
.user-info .phone { color: var(--muted); font-size: .82rem; font-family: monospace; }
.user-meta { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 6px; align-items: center; }

.badge { display: inline-block; padding: 2px 9px; border-radius: 10px; font-size: .72rem; font-weight: 700; }
.b-free     { background: rgba(126,133,155,.15); color: var(--muted); }
.b-basic    { background: rgba(92,214,111,.12);  color: var(--ok); }
.b-standard { background: rgba(91,180,255,.12);  color: var(--blue); }
.b-premium  { background: rgba(124,92,255,.15);  color: var(--accent); }
.b-inactive { background: rgba(255,107,107,.12); color: var(--err); }
.b-device   { background: rgba(255,200,87,.1);   color: var(--warn); font-family: monospace; }
.b-admin    { background: rgba(167,139,250,.18); color: #a78bfa; }

.meta-item { color: var(--muted); font-size: .78rem; }

/* ── Actions panel ──────────────── */
.user-actions { display: flex; flex-direction: column; gap: 6px; align-items: flex-end; }
.plan-form { display: flex; gap: 6px; align-items: center; }
.plan-select {
  padding: 5px 8px; background: var(--panel2); border: 1px solid var(--border);
  color: var(--text); border-radius: 7px; font-size: .8rem; width: auto;
}
.btn-sm {
  padding: 5px 12px; border-radius: 7px; font-size: .8rem; font-weight: 600;
  cursor: pointer; border: none;
}
.btn-set    { background: var(--accent); color: #fff; }
.btn-del    { background: transparent; color: var(--err); border: 1px solid rgba(255,107,107,.4); }
.btn-tog    { background: transparent; color: var(--warn); border: 1px solid rgba(255,200,87,.4); }
.btn-tog.deactivate { color: var(--ok); border-color: rgba(92,214,111,.4); }
.btn-adm    { background: transparent; color: #a78bfa; border: 1px solid rgba(167,139,250,.4); }
.btn-adm.revoke { color: var(--err); border-color: rgba(255,107,107,.4); }

/* expiry */
.exp-ok   { color: var(--ok); }
.exp-soon { color: var(--warn); }
.exp-none { color: var(--muted); }

/* empty / loading */
.empty-state { text-align: center; padding: 48px; color: var(--muted); font-size: .9rem; }

/* history modal */
.modal-backdrop {
  display: none; position: fixed; inset: 0; background: #000a;
  z-index: 1000; align-items: center; justify-content: center;
}
.modal-backdrop.open { display: flex; }
.modal {
  background: var(--panel); border: 1px solid var(--border); border-radius: 16px;
  padding: 24px; max-width: 560px; width: 95vw; max-height: 80vh; overflow-y: auto;
}
.modal h3 { margin: 0 0 14px; color: var(--text); }
.hist-row { padding: 8px 0; border-bottom: 1px solid var(--border); font-size: .83rem; }
.hist-row:last-child { border: none; }
.hist-title { font-weight: 600; color: var(--text); }
.hist-meta  { color: var(--muted); }
.progress-bar {
  height: 4px; background: var(--panel2); border-radius: 2px; margin-top: 4px; overflow: hidden;
}
.progress-fill { height: 100%; background: var(--accent); border-radius: 2px; }
</style>

<div class="up-page">
  <h1>👤 App Users</h1>
  <p class="sub">All registered RaddFlix app users and their subscription status</p>

  <!-- Stats -->
  <div class="stats-row">
    <div class="stat-tile">
      <div class="k">Total Users</div>
      <div class="v blue">{{ stats.total }}</div>
    </div>
    <div class="stat-tile">
      <div class="k">Paid Plans</div>
      <div class="v green">{{ stats.paid }}</div>
    </div>
    <div class="stat-tile">
      <div class="k">Free / Guest</div>
      <div class="v warn">{{ stats.free }}</div>
    </div>
    <div class="stat-tile">
      <div class="k">Inactive</div>
      <div class="v red">{{ stats.inactive }}</div>
    </div>
    <div class="stat-tile">
      <div class="k">Admins</div>
      <div class="v purple">{{ stats.admins }}</div>
    </div>
  </div>

  <!-- ── Admin Management ──────────────────────────────────── -->
  <div class="admin-box">
    <h2>🛡 Admin Users</h2>

    {% if admin_users %}
    <div class="admin-list">
      {% for a in admin_users %}
      <div class="admin-chip">
        <span class="num">{{ a.phone }}</span>
        <span class="uid">ID #{{ a.id }}</span>
        <form method="post" action="/app-users/{{ a.id }}/toggle-admin"
              onsubmit="return confirm('Revoke admin from {{ a.phone }}?')">
          <button class="revoke-btn" type="submit" title="Revoke admin">✕</button>
        </form>
      </div>
      {% endfor %}
    </div>
    {% else %}
    <p class="admin-none">No admin users yet.</p>
    {% endif %}

    <div class="grant-row">
      <input class="grant-input" id="grant-phone" type="tel"
             placeholder="Phone number (e.g. 03001234567)" maxlength="20">
      <button class="btn-grant" onclick="grantAdmin()">＋ Grant Admin</button>
    </div>
    <div class="flash-msg" id="grant-flash"></div>
  </div>

  <!-- Filters + Search -->
  <div class="filters">
    <a href="?filter=all" class="f-btn {{ 'active' if filter=='all' }}">All ({{ stats.total }})</a>
    <a href="?filter=paid" class="f-btn {{ 'active' if filter=='paid' }}">Paid</a>
    <a href="?filter=free" class="f-btn {{ 'active' if filter=='free' }}">Free</a>
    <a href="?filter=inactive" class="f-btn {{ 'active' if filter=='inactive' }}">Inactive</a>
    <a href="?filter=admin" class="f-btn admin-btn {{ 'active' if filter=='admin' }}">🛡 Admin</a>
    <input class="search-box" id="search-box" type="search" placeholder="Search phone…"
           value="{{ q or '' }}" oninput="filterCards(this.value)">
  </div>

  <!-- User list -->
  {% if not users %}
  <div class="empty-state">
    No users found.<br>
    <small>Users appear here after they register on the RaddFlix app.</small>
  </div>
  {% endif %}

  {% for u in users %}
  <div class="user-card {{ 'inactive' if not u.is_active }} {{ 'is-admin' if u.is_admin }}"
       data-phone="{{ u.phone }}">

    <!-- Avatar -->
    <div class="user-avatar">{{ u.phone[2] if u.phone|length > 2 else '?' }}</div>

    <!-- Info -->
    <div class="user-info">
      <div class="name">
        {{ u.phone }}
        {% if u.is_admin %}
        <span class="badge b-admin">🛡 ADMIN</span>
        {% endif %}
        {% if not u.is_active %}
        <span class="badge b-inactive">Deactivated</span>
        {% endif %}
      </div>
      <div class="phone">ID #{{ u.id }} &nbsp;·&nbsp; Joined {{ u.joined }}</div>

      <div class="user-meta">
        <!-- Plan badge -->
        {% if u.plan in ('basic','standard','premium') %}
        <span class="badge b-{{ u.plan }}">{{ u.plan.upper() }}</span>
        {% else %}
        <span class="badge b-free">FREE</span>
        {% endif %}

        <!-- Expiry -->
        {% if u.expires_at %}
        <span class="meta-item {{ u.exp_class }}">Expires {{ u.expires_str }}</span>
        {% endif %}

        <!-- Last login -->
        {% if u.last_login %}
        <span class="meta-item">Last login {{ u.last_login }}</span>
        {% else %}
        <span class="meta-item">Never logged in</span>
        {% endif %}

        <!-- Device -->
        {% if u.device_name %}
        <span class="badge b-device">📱 {{ u.device_name }}</span>
        {% endif %}
      </div>
    </div>

    <!-- Actions -->
    <div class="user-actions">
      <!-- Set plan -->
      <form class="plan-form" method="post" action="/app-users/{{ u.id }}/set-plan">
        <select class="plan-select" name="plan">
          <option value="free"     {{ 'selected' if u.plan=='free' }}>Free</option>
          <option value="basic"    {{ 'selected' if u.plan=='basic' }}>Basic</option>
          <option value="standard" {{ 'selected' if u.plan=='standard' }}>Standard</option>
          <option value="premium"  {{ 'selected' if u.plan=='premium' }}>Premium</option>
        </select>
        <select class="plan-select" name="days" style="width:70px">
          <option value="30">30d</option>
          <option value="60">60d</option>
          <option value="90">90d</option>
          <option value="365">1yr</option>
        </select>
        <button class="btn-sm btn-set" type="submit">Set</button>
      </form>

      <!-- Toggle admin -->
      <form method="post" action="/app-users/{{ u.id }}/toggle-admin"
            onsubmit="return confirm('{{ 'Grant admin to' if not u.is_admin else 'Revoke admin from' }} {{ u.phone }}?')">
        <button class="btn-sm btn-adm {{ 'revoke' if u.is_admin }}" type="submit">
          {{ '🛡 Grant Admin' if not u.is_admin else '✕ Revoke Admin' }}
        </button>
      </form>

      <!-- Toggle active -->
      <form method="post" action="/app-users/{{ u.id }}/toggle-active"
            onsubmit="return confirm('{{ 'Activate' if not u.is_active else 'Deactivate' }} this user?')">
        <button class="btn-sm btn-tog {{ '' if not u.is_active else 'deactivate' }}" type="submit">
          {{ '✓ Activate' if not u.is_active else '⊘ Deactivate' }}
        </button>
      </form>

      <!-- Watch history -->
      <button class="btn-sm" style="background:transparent;color:var(--blue);border:1px solid rgba(91,180,255,.3)"
              onclick="showHistory({{ u.id }}, '{{ u.phone }}')">History</button>

      <!-- Delete -->
      <form method="post" action="/app-users/{{ u.id }}/delete"
            onsubmit="return confirm('Permanently delete user {{ u.phone }} and ALL their data?')">
        <button class="btn-sm btn-del" type="submit">✕ Delete</button>
      </form>
    </div>
  </div>
  {% endfor %}
</div>

<!-- Watch History Modal -->
<div class="modal-backdrop" id="hist-modal">
  <div class="modal">
    <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:14px">
      <h3 id="hist-title">Watch History</h3>
      <button onclick="closeHistory()"
        style="background:none;border:none;color:var(--muted);font-size:1.2rem;cursor:pointer">✕</button>
    </div>
    <div id="hist-body"><div class="empty-state">Loading…</div></div>
  </div>
</div>

<script>
function filterCards(q) {
  q = q.toLowerCase().trim();
  document.querySelectorAll('.user-card').forEach(el => {
    const phone = (el.dataset.phone || '').toLowerCase();
    el.style.display = (!q || phone.includes(q)) ? '' : 'none';
  });
}

async function grantAdmin() {
  const phone = document.getElementById('grant-phone').value.trim();
  const flash  = document.getElementById('grant-flash');
  if (!phone) { showFlash('Enter a phone number first.', false); return; }
  try {
    const r = await fetch('/app-users/grant-admin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: 'phone=' + encodeURIComponent(phone)
    });
    const d = await r.json();
    if (d.ok) {
      showFlash('✓ ' + (d.message || 'Admin granted.'), true);
      setTimeout(() => location.reload(), 1200);
    } else {
      showFlash('✕ ' + (d.error || 'Failed.'), false);
    }
  } catch(e) {
    showFlash('✕ Network error.', false);
  }
}

function showFlash(msg, ok) {
  const el = document.getElementById('grant-flash');
  el.textContent = msg;
  el.className = 'flash-msg ' + (ok ? 'ok' : 'err');
  el.style.display = 'block';
  if (ok) setTimeout(() => { el.style.display = 'none'; }, 3000);
}

document.getElementById('grant-phone').addEventListener('keydown', e => {
  if (e.key === 'Enter') grantAdmin();
});

async function showHistory(userId, phone) {
  document.getElementById('hist-title').textContent = 'Watch History — ' + phone;
  document.getElementById('hist-body').innerHTML = '<div class="empty-state">Loading…</div>';
  document.getElementById('hist-modal').classList.add('open');
  try {
    const r = await fetch('/app-users/' + userId + '/history');
    const d = await r.json();
    if (!d.history || !d.history.length) {
      document.getElementById('hist-body').innerHTML = '<div class="empty-state">No watch history yet.</div>';
      return;
    }
    document.getElementById('hist-body').innerHTML = d.history.map(h => {
      const pct = h.duration_sec > 0 ? Math.min(100, Math.round(h.position_sec / h.duration_sec * 100)) : 0;
      return `<div class="hist-row">
        <div class="hist-title">${h.title || 'Unknown title'}</div>
        <div class="hist-meta">${h.filename || ''} &nbsp;·&nbsp; ${pct}% watched &nbsp;·&nbsp; ${h.watched_at || ''}</div>
        <div class="progress-bar"><div class="progress-fill" style="width:${pct}%"></div></div>
      </div>`;
    }).join('');
  } catch(e) {
    document.getElementById('hist-body').innerHTML = '<div class="empty-state">Failed to load history.</div>';
  }
}

function closeHistory() {
  document.getElementById('hist-modal').classList.remove('open');
}
document.getElementById('hist-modal').addEventListener('click', function(e) {
  if (e.target === this) closeHistory();
});
</script>
{% endblock %}
"""


def _fmt_time(ts, relative=False):
    if not ts:
        return None
    import datetime
    try:
        dt = datetime.datetime.fromtimestamp(int(ts))
        if relative:
            diff = time.time() - int(ts)
            if diff < 3600:
                return f"{int(diff/60)}m ago"
            if diff < 86400:
                return f"{int(diff/3600)}h ago"
            if diff < 86400 * 7:
                return f"{int(diff/86400)}d ago"
        return dt.strftime("%-d %b %Y")
    except Exception:
        return None


@bp.route("/")
@login_required
def index():
    filter_ = request.args.get("filter", "all")
    q = request.args.get("q", "").strip()

    with db.conn() as c:
        # All users with their latest subscription
        rows = c.execute("""
            SELECT
                u.id, u.phone, u.is_active, u.created_at, u.last_login_at,
                u.device_name, u.is_admin,
                s.plan, s.expires_at, s.is_active AS sub_active
            FROM app_users u
            LEFT JOIN app_subscriptions s
                ON s.id = (
                    SELECT id FROM app_subscriptions
                    WHERE user_id = u.id
                    ORDER BY created_at DESC LIMIT 1
                )
            ORDER BY u.is_admin DESC, u.id DESC
        """).fetchall()

    now = time.time()
    users = []
    for r in rows:
        plan = r["plan"] or "free"
        exp  = r["expires_at"]
        is_active = bool(r["is_active"])
        is_admin  = bool(r["is_admin"])

        # Expiry display
        expires_str = None
        exp_class   = "exp-none"
        if exp and plan != "free":
            expires_str = _fmt_time(exp)
            days_left   = (exp - now) / 86400
            if days_left < 0:
                exp_class = "exp-none"
                expires_str = f"Expired {_fmt_time(exp)}"
            elif days_left < 5:
                exp_class = "exp-soon"
            else:
                exp_class = "exp-ok"

        users.append({
            "id":          r["id"],
            "phone":       r["phone"],
            "is_active":   is_active,
            "is_admin":    is_admin,
            "plan":        plan,
            "expires_at":  exp,
            "expires_str": expires_str,
            "exp_class":   exp_class,
            "joined":      _fmt_time(r["created_at"]) or "?",
            "last_login":  _fmt_time(r["last_login_at"], relative=True),
            "device_name": r["device_name"],
        })

    # Collect admin users for the top admin box (always from full list)
    admin_users = [u for u in users if u["is_admin"]]

    # Apply filter
    if filter_ == "paid":
        users = [u for u in users if u["plan"] not in ("free",)]
    elif filter_ == "free":
        users = [u for u in users if u["plan"] == "free"]
    elif filter_ == "inactive":
        users = [u for u in users if not u["is_active"]]
    elif filter_ == "admin":
        users = [u for u in users if u["is_admin"]]

    # Stats (always from full list)
    with db.conn() as c:
        all_rows = c.execute("""
            SELECT u.is_active, u.is_admin,
                   COALESCE((SELECT plan FROM app_subscriptions WHERE user_id=u.id ORDER BY created_at DESC LIMIT 1),'free') AS plan
            FROM app_users u
        """).fetchall()

    stats = {
        "total":    len(all_rows),
        "paid":     sum(1 for r in all_rows if r["plan"] not in ("free",)),
        "free":     sum(1 for r in all_rows if r["plan"] == "free"),
        "inactive": sum(1 for r in all_rows if not r["is_active"]),
        "admins":   sum(1 for r in all_rows if r["is_admin"]),
    }

    return render_template_string(_HTML,
        users=users, stats=stats, filter=filter_, q=q,
        admin_users=admin_users, active="app_users")


@bp.route("/<int:user_id>/set-plan", methods=["POST"])
@login_required
def set_plan(user_id):
    plan = request.form.get("plan", "free")
    days = int(request.form.get("days", "30"))
    now  = int(time.time())
    exp  = now + days * 86400 if plan != "free" else None

    with db.conn() as c:
        # Deactivate old subscriptions
        c.execute("UPDATE app_subscriptions SET is_active=0 WHERE user_id=?", (user_id,))
        # Insert new subscription
        c.execute("""
            INSERT INTO app_subscriptions (user_id, plan, started_at, expires_at, is_active)
            VALUES (?, ?, ?, ?, 1)
        """, (user_id, plan, now, exp))

    log.info("Admin set user %d plan → %s (%d days)", user_id, plan, days)
    return redirect(url_for("app_users_panel.index"))


@bp.route("/<int:user_id>/toggle-active", methods=["POST"])
@login_required
def toggle_active(user_id):
    with db.conn() as c:
        row = c.execute("SELECT is_active FROM app_users WHERE id=?", (user_id,)).fetchone()
        if row:
            new_state = 0 if row["is_active"] else 1
            c.execute("UPDATE app_users SET is_active=? WHERE id=?", (new_state, user_id))
    return redirect(url_for("app_users_panel.index"))


@bp.route("/<int:user_id>/toggle-admin", methods=["POST"])
@login_required
def toggle_admin(user_id):
    with db.conn() as c:
        row = c.execute("SELECT is_admin, phone FROM app_users WHERE id=?", (user_id,)).fetchone()
        if row:
            new_state = 0 if row["is_admin"] else 1
            c.execute("UPDATE app_users SET is_admin=? WHERE id=?", (new_state, user_id))
            log.info("Admin %s admin flag for user %d (%s)", "granted" if new_state else "revoked", user_id, row["phone"])
    return redirect(url_for("app_users_panel.index"))


@bp.route("/grant-admin", methods=["POST"])
@login_required
def grant_admin():
    """Grant admin by phone number — returns JSON so the JS can update the UI inline."""
    phone = (request.form.get("phone") or "").strip()
    if not phone:
        return jsonify({"ok": False, "error": "Phone number is required."}), 400

    with db.conn() as c:
        row = c.execute("SELECT id, phone, is_admin FROM app_users WHERE phone=?", (phone,)).fetchone()
        if not row:
            return jsonify({
                "ok": False,
                "error": f"No account found for {phone}. The user must log into the app first to create an account."
            }), 404
        if row["is_admin"]:
            return jsonify({"ok": False, "error": f"{phone} is already an admin."}), 409
        c.execute("UPDATE app_users SET is_admin=1 WHERE id=?", (row["id"],))
        log.info("Admin granted admin flag to user %d (%s)", row["id"], phone)

    return jsonify({"ok": True, "message": f"Admin granted to {phone}."})


@bp.route("/<int:user_id>/delete", methods=["POST"])
@login_required
def delete_user(user_id):
    with db.conn() as c:
        c.execute("DELETE FROM app_subscriptions WHERE user_id=?", (user_id,))
        c.execute("DELETE FROM app_refresh_tokens WHERE user_id=?", (user_id,))
        c.execute("DELETE FROM tid_payments WHERE user_id=?", (user_id,))
        try:
            c.execute("DELETE FROM watch_history WHERE user_id=?", (user_id,))
        except Exception:
            pass
        c.execute("DELETE FROM app_users WHERE id=?", (user_id,))
    log.info("Admin deleted user %d", user_id)
    return redirect(url_for("app_users_panel.index"))


@bp.route("/<int:user_id>/history")
@login_required
def user_history(user_id):
    try:
        with db.conn() as c:
            rows = c.execute("""
                SELECT wh.position_sec, wh.duration_sec, wh.updated_at,
                       f.filename, t.title
                FROM watch_history wh
                LEFT JOIN files f ON f.id = wh.file_id
                LEFT JOIN titles t ON t.id = f.title_id
                WHERE wh.user_id = ?
                ORDER BY wh.updated_at DESC
                LIMIT 50
            """, (user_id,)).fetchall()
        history = []
        for r in rows:
            history.append({
                "title":        r["title"],
                "filename":     r["filename"],
                "position_sec": r["position_sec"],
                "duration_sec": r["duration_sec"] or 0,
                "watched_at":   _fmt_time(r["updated_at"], relative=True),
            })
        return jsonify({"ok": True, "history": history})
    except Exception as e:
        return jsonify({"ok": False, "history": [], "error": str(e)})


@bp.route("/api/stats")
@login_required
def api_stats():
    """Quick stats for the dashboard widget."""
    with db.conn() as c:
        total = c.execute("SELECT COUNT(*) FROM app_users").fetchone()[0]
        active_subs = c.execute(
            "SELECT COUNT(*) FROM app_subscriptions "
            "WHERE is_active=1 AND expires_at > strftime('%s','now')"
        ).fetchone()[0]
        try:
            pending_tids = c.execute(
                "SELECT COUNT(*) FROM tid_payments WHERE status='pending'"
            ).fetchone()[0]
        except Exception:
            pending_tids = 0
    return jsonify({"ok": True, "total": total, "active_subs": active_subs, "pending_tids": pending_tids})

