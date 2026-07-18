"""Subscriptions Panel — view all active, expiring, expired subscriptions."""
from __future__ import annotations
import time, datetime, logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.subscriptions")
bp = Blueprint("subscriptions", __name__, url_prefix="/subscriptions")

_HTML = """
{% extends "base.html" %}
{% set active="subscriptions" %}
{% block title %}Subscriptions{% endblock %}
{% block content %}
<style>
.sub-page { max-width: 1100px; margin: 0 auto; }
.sub-page h2 { margin: 0 0 4px; }
.sub-sub { color: var(--muted); font-size: .85rem; margin-bottom: 24px; }
.stat-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 14px; margin-bottom: 24px; }
@media(max-width:700px){ .stat-grid { grid-template-columns: repeat(2,1fr); } }
.s-tile { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 16px 18px; }
.s-tile .k { font-size: .75rem; text-transform: uppercase; letter-spacing: .5px; color: var(--muted); }
.s-tile .v { font-size: 2rem; font-weight: 700; margin-top: 4px; }
.tabs { display: flex; gap: 8px; margin-bottom: 20px; flex-wrap: wrap; }
.tab-btn { padding: 6px 16px; border-radius: 8px; border: 1px solid var(--border); background: var(--panel); color: var(--muted); text-decoration: none; font-size: .85rem; }
.tab-btn.active { background: var(--accent); color: #fff; border-color: var(--accent); }
.tab-btn.warn.active { background: var(--warn); color: #000; border-color: var(--warn); }
.tab-btn.err.active  { background: var(--err);  color: #fff; border-color: var(--err); }
.sub-table { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; }
.sub-table table { width: 100%; border-collapse: collapse; }
.sub-table th { background: var(--panel2); padding: 10px 14px; font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; text-align: left; }
.sub-table td { padding: 10px 14px; font-size: 13px; border-top: 1px solid var(--border); vertical-align: middle; }
.plan-badge { padding: 2px 9px; border-radius: 10px; font-size: 11px; font-weight: 700; }
.plan-basic    { background: rgba(212,120,74,.15);  color: #D4784A; }
.plan-standard { background: rgba(124,92,255,.15); color: #7c5cff; }
.plan-premium  { background: rgba(0,200,83,.15);   color: var(--ok); }
.plan-free     { background: rgba(126,133,155,.15);color: var(--muted); }
.expiry-ok   { color: var(--ok); }
.expiry-warn { color: var(--warn); }
.expiry-err  { color: var(--err); }
.empty { text-align: center; color: var(--muted); padding: 40px; font-size: .9rem; }
.btn-sm { padding: 4px 10px; font-size: 12px; border-radius: 6px; border: none; cursor: pointer; font-weight: 600; }
.btn-extend { background: rgba(0,200,83,.15); color: var(--ok); border: 1px solid rgba(0,200,83,.3); }
.btn-revoke  { background: rgba(255,107,107,.1); color: var(--err); border: 1px solid rgba(255,107,107,.3); }
</style>

<div class="sub-page">
  <h2>📋 Subscriptions</h2>
  <p class="sub-sub">Manage all subscriber plans, extend or revoke access.</p>

  <div class="stat-grid">
    <div class="s-tile">
      <div class="k">Active</div>
      <div class="v" style="color:var(--ok)">{{ active_count }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Expiring ≤7d</div>
      <div class="v" style="color:var(--warn)">{{ expiring_count }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Expired</div>
      <div class="v" style="color:var(--err)">{{ expired_count }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Free Users</div>
      <div class="v" style="color:var(--muted)">{{ free_count }}</div>
    </div>
  </div>

  <div class="tabs">
    <a href="?tab=active"   class="tab-btn {% if tab=='active' %}active{% endif %}">Active ({{ active_count }})</a>
    <a href="?tab=expiring" class="tab-btn warn {% if tab=='expiring' %}active{% endif %}">⚠ Expiring Soon ({{ expiring_count }})</a>
    <a href="?tab=expired"  class="tab-btn err {% if tab=='expired' %}active{% endif %}">Expired ({{ expired_count }})</a>
    <a href="?tab=all"      class="tab-btn {% if tab=='all' %}active{% endif %}">All</a>
  </div>

  {% if not rows %}
    <div class="empty">No {{ tab }} subscriptions found.</div>
  {% else %}
  <div class="sub-table">
    <div style="overflow-x:auto">
    <table>
      <thead><tr>
        <th>Phone</th><th>Name</th><th>Plan</th>
        <th>Started</th><th>Expires</th><th>Days Left</th><th>Actions</th>
      </tr></thead>
      <tbody>
      {% for r in rows %}
      <tr>
        <td style="font-family:monospace">{{ r.phone }}</td>
        <td>{{ r.name or '—' }}</td>
        <td><span class="plan-badge plan-{{ r.plan or 'free' }}">{{ (r.plan or 'free') | upper }}</span></td>
        <td style="color:var(--muted)">{{ r.started_human }}</td>
        <td style="color:var(--muted)">{{ r.expires_human }}</td>
        <td class="{% if r.days_left <= 0 %}expiry-err{% elif r.days_left <= 7 %}expiry-warn{% else %}expiry-ok{% endif %}">
          {% if r.days_left <= 0 %}Expired{% else %}{{ r.days_left }}d{% endif %}
        </td>
        <td style="white-space:nowrap;display:flex;gap:6px">
          <form method="post" action="/subscriptions/{{ r.user_id }}/extend" style="display:inline">
            <input type="hidden" name="days" value="30">
            <button class="btn-sm btn-extend" type="submit">+30d</button>
          </form>
          {% if r.sub_id %}
          <form method="post" action="/subscriptions/{{ r.sub_id }}/revoke" style="display:inline">
            <button class="btn-sm btn-revoke" type="submit" onclick="return confirm('Revoke this subscription?')">Revoke</button>
          </form>
          {% endif %}
        </td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
    </div>
  </div>
  {% endif %}
</div>
{% endblock %}
"""

def _fmt(ts):
    if not ts: return "—"
    return datetime.datetime.fromtimestamp(int(ts)).strftime("%d %b %Y")

@bp.route("/")
@login_required
def index():
    now = int(time.time())
    tab = request.args.get("tab", "active")

    with db.conn() as c:
        active_count  = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at > ?", (now,)).fetchone()["n"]
        expiring_count= c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at BETWEEN ? AND ?", (now, now+7*86400)).fetchone()["n"]
        expired_count = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at <= ?", (now,)).fetchone()["n"]
        free_count    = c.execute("""
            SELECT COUNT(*) AS n FROM app_users u
            WHERE NOT EXISTS (SELECT 1 FROM app_subscriptions s WHERE s.user_id=u.id AND s.is_active=1 AND s.expires_at > ?)
        """, (now,)).fetchone()["n"]

        if tab == "active":
            where = "s.is_active=1 AND s.expires_at > ?"
            params = (now,)
        elif tab == "expiring":
            where = "s.is_active=1 AND s.expires_at BETWEEN ? AND ?"
            params = (now, now + 7*86400)
        elif tab == "expired":
            where = "s.is_active=1 AND s.expires_at <= ?"
            params = (now,)
        else:
            where = "1=1"
            params = ()

        rows = c.execute(f"""
            SELECT u.id as user_id, u.phone, NULL as name,
                   s.id as sub_id, s.plan, s.started_at, s.expires_at
            FROM app_users u
            LEFT JOIN app_subscriptions s ON s.user_id=u.id
            WHERE {where}
            ORDER BY s.expires_at ASC
            LIMIT 200
        """, params).fetchall()

    result = []
    for r in rows:
        d = dict(r)
        d["started_human"] = _fmt(r["started_at"])
        d["expires_human"] = _fmt(r["expires_at"])
        d["days_left"] = max(0, int((r["expires_at"] - now) / 86400)) if r["expires_at"] else 0
        result.append(d)

    return render_template_string(_HTML,
        tab=tab, rows=result,
        active_count=active_count, expiring_count=expiring_count,
        expired_count=expired_count, free_count=free_count)


@bp.route("/<int:user_id>/extend", methods=["POST"])
@login_required
def extend(user_id: int):
    days = int(request.form.get("days", 30))
    now  = int(time.time())
    with db.conn() as c:
        sub = c.execute("SELECT * FROM app_subscriptions WHERE user_id=? ORDER BY expires_at DESC LIMIT 1", (user_id,)).fetchone()
        if sub:
            new_exp = max(sub["expires_at"], now) + days * 86400
            c.execute("UPDATE app_subscriptions SET expires_at=? WHERE id=?", (new_exp, sub["id"]))
        else:
            c.execute("INSERT INTO app_subscriptions(user_id,plan,started_at,expires_at,is_active,created_at) VALUES(?,?,?,?,1,?)",
                      (user_id, sub["plan"] if sub else "basic", now, now + days*86400, now))
    log.info("Extended user %s by %d days", user_id, days)
    return redirect(url_for("subscriptions.index", tab=request.args.get("tab","active")))


@bp.route("/<int:sub_id>/revoke", methods=["POST"])
@login_required
def revoke(sub_id: int):
    with db.conn() as c:
        c.execute("UPDATE app_subscriptions SET is_active=0 WHERE id=?", (sub_id,))
    log.info("Revoked subscription %s", sub_id)
    return redirect(url_for("subscriptions.index", tab=request.args.get("tab","active")))


@bp.route("/api/stats")
@login_required
def api_stats():
    now = int(time.time())
    with db.conn() as c:
        return jsonify({
            "active":   c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at > ?", (now,)).fetchone()["n"],
            "expiring": c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at BETWEEN ? AND ?", (now, now+7*86400)).fetchone()["n"],
            "expired":  c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at <= ?", (now,)).fetchone()["n"],
        })
