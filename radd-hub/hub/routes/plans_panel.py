"""Plans & Pricing Admin Panel — Full CRUD for subscription plans.

Create / Edit use dedicated server-rendered pages (no JavaScript modal).
Toggle and Delete use direct POST forms (unchanged).
"""
from __future__ import annotations
import time, json, logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.plans_panel")
bp = Blueprint("plans_panel", __name__, url_prefix="/plans")

COLORS = ['#7c5cff','#E8002D','#00C853','#FF6D00','#00B0FF','#FFD600','#AA00FF','#00E5FF','#FF4081','#1de9b6']

# ── Shared CSS ────────────────────────────────────────────────────────────────
_SHARED_CSS = """
<style>
.plans-page{max-width:1200px;margin:0 auto}
.plans-page h2{margin:0 0 4px}
.sub-sub{color:var(--muted);font-size:.85rem;margin-bottom:24px}
.stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:28px}
@media(max-width:700px){.stat-grid{grid-template-columns:repeat(2,1fr)}}
.s-tile{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:16px 18px}
.s-tile .k{font-size:.75rem;text-transform:uppercase;letter-spacing:.5px;color:var(--muted)}
.s-tile .v{font-size:2rem;font-weight:700;margin-top:4px}
.plans-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px;margin-bottom:28px}
.plan-card{background:var(--panel);border:1px solid var(--border);border-radius:16px;overflow:hidden;position:relative;transition:transform .15s,box-shadow .15s}
.plan-card:hover{transform:translateY(-2px);box-shadow:0 8px 32px #0004}
.plan-card.inactive{opacity:.55}
.plan-card-header{padding:22px 22px 16px;position:relative}
.plan-card-header::before{content:'';position:absolute;top:0;left:0;right:0;height:4px;background:var(--card-color)}
.plan-badge-label{display:inline-block;padding:2px 10px;border-radius:20px;font-size:10px;font-weight:700;letter-spacing:1px;margin-bottom:10px;text-transform:uppercase;background:var(--card-color);color:#fff}
.plan-name{font-size:22px;font-weight:700;margin:0 0 4px}
.plan-desc{color:var(--muted);font-size:.8rem;margin:0}
.plan-price-row{display:flex;align-items:baseline;gap:6px;margin:16px 0 0}
.plan-price{font-size:36px;font-weight:800;color:var(--card-color)}
.plan-price-unit{color:var(--muted);font-size:.8rem}
.plan-card-body{padding:0 22px 22px}
.plan-features{list-style:none;padding:0;margin:16px 0}
.plan-features li{padding:6px 0;font-size:.85rem;color:var(--muted);display:flex;gap:8px;align-items:center;border-bottom:1px solid var(--border)}
.plan-features li:last-child{border-bottom:none}
.plan-features li::before{content:'✓';color:var(--card-color);font-weight:700;flex-shrink:0}
.plan-meta{display:flex;gap:10px;flex-wrap:wrap;margin:12px 0}
.plan-chip{background:var(--panel2);border:1px solid var(--border);border-radius:8px;padding:4px 10px;font-size:11px;color:var(--muted)}
.plan-actions{display:flex;gap:8px;margin-top:16px}
.btn-edit{display:inline-block;text-align:center;background:rgba(124,92,255,.12);color:#7c5cff;border:1px solid rgba(124,92,255,.3);padding:6px 14px;border-radius:7px;font-size:12px;font-weight:600;cursor:pointer;flex:1;text-decoration:none;line-height:1.6}
.btn-edit:hover{background:rgba(124,92,255,.2)}
.btn-toggle-on {background:rgba(92,214,111,.12);color:var(--ok);border:1px solid rgba(92,214,111,.3);padding:6px 10px;border-radius:7px;font-size:12px;font-weight:600;cursor:pointer}
.btn-toggle-on:hover{background:rgba(92,214,111,.2);filter:none}
.btn-toggle-off{background:rgba(255,107,107,.08);color:var(--err);border:1px solid rgba(255,107,107,.25);padding:6px 10px;border-radius:7px;font-size:12px;font-weight:600;cursor:pointer}
.btn-toggle-off:hover{background:rgba(255,107,107,.15);filter:none}
.btn-del{background:rgba(255,107,107,.08);color:var(--err);border:1px solid rgba(255,107,107,.25);padding:6px 10px;border-radius:7px;font-size:12px;font-weight:600;cursor:pointer}
.btn-del:hover{background:rgba(255,107,107,.15);filter:none}
.add-plan-card{display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:300px;border-radius:16px;border:2px dashed var(--border);text-decoration:none;transition:border-color .15s,background .15s}
.add-plan-card:hover{border-color:var(--accent);background:rgba(124,92,255,.04)}
.add-plan-icon{font-size:40px;margin-bottom:12px;color:var(--muted)}
.add-plan-text{color:var(--muted);font-size:.9rem}
/* Form page */
.form-page{max-width:600px;margin:0 auto}
.form-page h2{margin:0 0 4px}
.plan-form-card{background:var(--panel);border:1px solid var(--border);border-radius:16px;padding:28px;margin-top:20px}
.pf-row{margin-bottom:16px}
.pf-row label{display:block;margin-bottom:5px;color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:.5px}
.pf-row input,.pf-row textarea,.pf-row select{width:100%;padding:10px 12px;background:var(--panel2);border:1px solid var(--border);color:var(--text);border-radius:8px;font-size:13px;font-family:inherit;box-sizing:border-box}
.pf-row input:focus,.pf-row textarea:focus{outline:none;border-color:var(--accent)}
.pf-2col{display:grid;grid-template-columns:1fr 1fr;gap:12px}
@media(max-width:500px){.pf-2col{grid-template-columns:1fr}}
.color-grid{display:flex;gap:10px;flex-wrap:wrap;margin-top:6px}
.color-swatch{display:flex;flex-direction:column;align-items:center;gap:4px;cursor:pointer}
.color-swatch input[type=radio]{display:none}
.color-swatch span{display:block;width:34px;height:34px;border-radius:50%;border:3px solid transparent;transition:border-color .12s}
.color-swatch input[type=radio]:checked + span{border-color:#fff;box-shadow:0 0 0 2px var(--accent)}
.color-swatch:hover span{border-color:#aaa}
.form-actions{display:flex;gap:10px;margin-top:24px;justify-content:flex-end}
.btn-back{display:inline-block;padding:9px 18px;border-radius:8px;font-size:13px;font-weight:600;text-decoration:none;color:var(--muted);background:var(--panel2);border:1px solid var(--border)}
.btn-back:hover{color:var(--text)}
</style>
"""

# ── Index page ────────────────────────────────────────────────────────────────
_INDEX_HTML = """
{% extends "base.html" %}
{% set active="plans" %}
{% block title %}Plans & Pricing{% endblock %}
{% block content %}
""" + _SHARED_CSS + """
<div class="plans-page">
  <div class="h-row">
    <div>
      <h2>💎 Plans &amp; Pricing</h2>
      <p class="sub-sub">Manage subscription plans, pricing, features, and device limits.</p>
    </div>
  </div>

  <div class="stat-grid">
    <div class="s-tile"><div class="k">Total Plans</div><div class="v">{{ plans|length }}</div></div>
    <div class="s-tile"><div class="k">Active Plans</div><div class="v" style="color:var(--ok)">{{ plans|selectattr('is_active')|list|length }}</div></div>
    <div class="s-tile"><div class="k">Total Subscribers</div><div class="v" style="color:var(--accent)">{{ total_subs }}</div></div>
    <div class="s-tile"><div class="k">Monthly Revenue</div><div class="v" style="color:var(--warn)">₨{{ "{:,}".format(monthly_rev) }}</div></div>
  </div>

  {% if ok_msg %}
  <div class="card" style="background:rgba(92,214,111,.08);border-color:rgba(92,214,111,.3);color:var(--ok);margin-bottom:20px;padding:14px 18px;font-weight:600">
    ✓ {{ ok_msg }}
  </div>
  {% endif %}

  <div class="plans-grid">
    {% for p in plans %}
    <div class="plan-card {% if not p.is_active %}inactive{% endif %}" style="--card-color:{{ p.color or '#7c5cff' }}">
      <div class="plan-card-header">
        {% if p.badge %}<div class="plan-badge-label">{{ p.badge }}</div><br>{% endif %}
        <div class="plan-name">{{ p.name }}</div>
        <div class="plan-desc">{{ p.description or '' }}</div>
        <div class="plan-price-row">
          <span class="plan-price">₨{{ "{:,}".format(p.price_pkr|int) }}</span>
          <span class="plan-price-unit">/ {{ p.duration_days }} days</span>
        </div>
      </div>
      <div class="plan-card-body">
        <div class="plan-meta">
          <span class="plan-chip">📱 {{ p.max_devices }} device{{ 's' if p.max_devices != 1 }}</span>
          <span class="plan-chip">📅 {{ p.duration_days }}d</span>
          {% if p.monthly_limit_gb and p.monthly_limit_gb > 0 %}
          <span class="plan-chip">📦 {{ p.monthly_limit_gb }}GB/mo</span>
          {% else %}
          <span class="plan-chip">📦 Unlimited</span>
          {% endif %}
          <span class="plan-chip {% if p.is_active %}b-ok{% else %}b-err{% endif %}">
            {{ '● Active' if p.is_active else '○ Disabled' }}
          </span>
        </div>
        {% set feats = p.features_list %}
        {% if feats %}
        <ul class="plan-features">
          {% for f in feats[:5] %}<li>{{ f }}</li>{% endfor %}
        </ul>
        {% endif %}
        <div class="plan-meta" style="color:var(--muted);font-size:11px">{{ p.sub_count }} active subscribers</div>
        <div class="plan-actions">
          <a class="btn-edit" href="/plans/{{ p.id }}/edit_form">✏ Edit</a>
          <form method="post" action="/plans/{{ p.id }}/toggle" style="display:contents">
            <button class="{% if p.is_active %}btn-toggle-off{% else %}btn-toggle-on{% endif %}" type="submit">{{ '⏸' if p.is_active else '▶' }}</button>
          </form>
          <form method="post" action="/plans/{{ p.id }}/delete" style="display:contents" onsubmit="return confirm('Delete this plan?')">
            <button class="btn-del" type="submit">🗑</button>
          </form>
        </div>
      </div>
    </div>
    {% endfor %}

    <a class="add-plan-card" href="/plans/new">
      <div class="add-plan-icon">＋</div>
      <div class="add-plan-text">Add New Plan</div>
    </a>
  </div>

  <div class="card">
    <h3>📊 Subscribers by Plan</h3>
    <div class="table-wrap">
    <table>
      <thead><tr><th>Plan</th><th>Price</th><th>Active Subs</th><th>Monthly Revenue</th><th>Status</th></tr></thead>
      <tbody>
      {% for p in plans %}
      <tr>
        <td><span style="color:{{ p.color or '#7c5cff' }};font-weight:700">{{ p.name }}</span></td>
        <td>₨{{ "{:,}".format(p.price_pkr|int) }}</td>
        <td>{{ p.sub_count }}</td>
        <td>₨{{ "{:,}".format((p.price_pkr * p.sub_count)|int) }}</td>
        <td><span class="badge {% if p.is_active %}b-ok{% else %}b-err{% endif %}">{{ 'Active' if p.is_active else 'Disabled' }}</span></td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
    </div>
  </div>
</div>
{% endblock %}
"""

# ── Shared form fields template (used by both new + edit pages) ───────────────
_FORM_FIELDS = """
      <div class="pf-row">
        <label>Plan Name *</label>
        <input name="name" required placeholder="e.g. Premium" value="{{ plan.name if plan else '' }}">
      </div>
      <div class="pf-2col">
        <div class="pf-row">
          <label>Price (PKR) *</label>
          <input name="price_pkr" type="number" min="0" step="1" required placeholder="299"
                 value="{{ plan.price_pkr if plan else '' }}">
        </div>
        <div class="pf-row">
          <label>Duration (days)</label>
          <input name="duration_days" type="number" min="1"
                 value="{{ plan.duration_days if plan else 30 }}">
        </div>
      </div>
      <div class="pf-2col">
        <div class="pf-row">
          <label>Max Devices</label>
          <input name="max_devices" type="number" min="1"
                 value="{{ plan.max_devices if plan else 1 }}">
        </div>
        <div class="pf-row">
          <label>Monthly Data Limit (GB, 0 = unlimited)</label>
          <input name="monthly_limit_gb" type="number" min="0" step="0.1"
                 value="{{ plan.monthly_limit_gb if plan else 0 }}">
        </div>
      </div>
      <div class="pf-row">
        <label>Description</label>
        <input name="description" placeholder="Short description for internal use"
               value="{{ plan.description or '' if plan else '' }}">
      </div>
      <div class="pf-row">
        <label>Badge Label (optional — e.g. POPULAR, BEST VALUE)</label>
        <input name="badge" placeholder="POPULAR / BEST VALUE / NEW"
               value="{{ plan.badge or '' if plan else '' }}">
      </div>
      <div class="pf-row">
        <label>Features (one per line — shown in app)</label>
        <textarea name="features" rows="5" placeholder="HD quality&#10;2 devices&#10;30-day access">{{ plan.features_list|join('\n') if plan else '' }}</textarea>
      </div>
      <div class="pf-row">
        <label>Card Colour</label>
        <div class="color-grid">
          {% for c in colors %}
          <label class="color-swatch">
            <input type="radio" name="color" value="{{ c }}"
              {% if plan and plan.color == c %}checked
              {% elif not plan and loop.first %}checked{% endif %}>
            <span style="background:{{ c }}"></span>
          </label>
          {% endfor %}
        </div>
      </div>
"""

# ── New plan page ─────────────────────────────────────────────────────────────
_NEW_HTML = """
{% extends "base.html" %}
{% set active="plans" %}
{% block title %}New Plan{% endblock %}
{% block content %}
""" + _SHARED_CSS + """
<div class="form-page">
  <div class="h-row">
    <div>
      <h2>💎 New Plan</h2>
      <p class="sub-sub">Fill in the details and click Save.</p>
    </div>
  </div>
  <div class="plan-form-card">
    <form method="post" action="/plans/create">
""" + _FORM_FIELDS + """
      <div class="form-actions">
        <a class="btn-back" href="/plans/">← Back</a>
        <button type="submit">💾 Save Plan</button>
      </div>
    </form>
  </div>
</div>
{% endblock %}
"""

# ── Edit plan page ────────────────────────────────────────────────────────────
_EDIT_HTML = """
{% extends "base.html" %}
{% set active="plans" %}
{% block title %}Edit Plan{% endblock %}
{% block content %}
""" + _SHARED_CSS + """
<div class="form-page">
  <div class="h-row">
    <div>
      <h2>✏ Edit Plan — {{ plan.name }}</h2>
      <p class="sub-sub">Update the fields below and click Save.</p>
    </div>
  </div>
  <div class="plan-form-card">
    <form method="post" action="/plans/{{ plan.id }}/edit">
""" + _FORM_FIELDS + """
      <div class="form-actions">
        <a class="btn-back" href="/plans/">← Back</a>
        <button type="submit">💾 Save Changes</button>
      </div>
    </form>
  </div>
</div>
{% endblock %}
"""

# ── Helpers ───────────────────────────────────────────────────────────────────
def _plan_data(plans_raw, now):
    result = []
    for p in plans_raw:
        d = dict(p)
        try:
            d['features_list'] = json.loads(p['features_json'] or '[]')
        except Exception:
            d['features_list'] = []
        result.append(d)
    return result

_OK_MESSAGES = {
    'created': 'Plan created successfully.',
    'updated': 'Plan updated successfully.',
    'deleted': 'Plan deleted.',
    'toggled': 'Plan status updated.',
}

# ── Routes ────────────────────────────────────────────────────────────────────

@bp.route("/")
@login_required
def index():
    now = int(time.time())
    with db.conn() as c:
        plans_raw = c.execute(
            "SELECT p.*, (SELECT COUNT(*) FROM app_subscriptions s "
            "WHERE s.plan=LOWER(p.name) AND s.is_active=1 AND s.expires_at>?) AS sub_count "
            "FROM plans p ORDER BY p.price_pkr ASC",
            (now,)
        ).fetchall()
        total_subs = c.execute(
            "SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at>?",
            (now,)
        ).fetchone()["n"]

    plans = _plan_data(plans_raw, now)
    monthly_rev = sum(p['price_pkr'] * p['sub_count'] for p in plans if p['is_active'])
    ok_msg = _OK_MESSAGES.get(request.args.get('ok', ''), '')
    return render_template_string(_INDEX_HTML, plans=plans, total_subs=total_subs,
                                   monthly_rev=int(monthly_rev), ok_msg=ok_msg)


@bp.route("/new")
@login_required
def new():
    return render_template_string(_NEW_HTML, plan=None, colors=COLORS)


@bp.route("/<int:plan_id>/edit_form")
@login_required
def edit_form(plan_id: int):
    with db.conn() as c:
        row = c.execute("SELECT * FROM plans WHERE id=?", (plan_id,)).fetchone()
    if not row:
        return redirect(url_for('plans_panel.index'))
    plan = dict(row)
    try:
        plan['features_list'] = json.loads(plan.get('features_json') or '[]')
    except Exception:
        plan['features_list'] = []
    return render_template_string(_EDIT_HTML, plan=plan, colors=COLORS)


@bp.route("/create", methods=["POST"])
@login_required
def create():
    d = request.form
    feats = [f.strip() for f in (d.get('features', '').strip().splitlines()) if f.strip()]
    with db.conn() as c:
        c.execute(
            "INSERT INTO plans(name,price_pkr,monthly_limit_gb,max_devices,duration_days,"
            "description,badge,color,features_json,is_active,created_at) "
            "VALUES(?,?,?,?,?,?,?,?,?,1,?)",
            (d.get('name', '').strip(),
             float(d.get('price_pkr', 0) or 0),
             float(d.get('monthly_limit_gb', 0) or 0),
             int(d.get('max_devices', 1) or 1),
             int(d.get('duration_days', 30) or 30),
             d.get('description', '').strip(),
             d.get('badge', '').strip().upper(),
             d.get('color', '#7c5cff'),
             json.dumps(feats),
             int(time.time()))
        )
    log.info("Created plan: %s", d.get('name'))
    return redirect(url_for('plans_panel.index') + '?ok=created')


@bp.route("/<int:plan_id>/edit", methods=["POST"])
@login_required
def edit(plan_id: int):
    d = request.form
    feats = [f.strip() for f in (d.get('features', '').strip().splitlines()) if f.strip()]
    with db.conn() as c:
        c.execute(
            "UPDATE plans SET name=?,price_pkr=?,monthly_limit_gb=?,max_devices=?,"
            "duration_days=?,description=?,badge=?,color=?,features_json=? WHERE id=?",
            (d.get('name', '').strip(),
             float(d.get('price_pkr', 0) or 0),
             float(d.get('monthly_limit_gb', 0) or 0),
             int(d.get('max_devices', 1) or 1),
             int(d.get('duration_days', 30) or 30),
             d.get('description', '').strip(),
             d.get('badge', '').strip().upper(),
             d.get('color', '#7c5cff'),
             json.dumps(feats),
             plan_id)
        )
    log.info("Updated plan #%d", plan_id)
    return redirect(url_for('plans_panel.index') + '?ok=updated')


@bp.route("/<int:plan_id>/toggle", methods=["POST"])
@login_required
def toggle(plan_id: int):
    with db.conn() as c:
        cur = c.execute("SELECT is_active FROM plans WHERE id=?", (plan_id,)).fetchone()
        if cur:
            c.execute("UPDATE plans SET is_active=? WHERE id=?",
                      (0 if cur['is_active'] else 1, plan_id))
    return redirect(url_for('plans_panel.index') + '?ok=toggled')


@bp.route("/<int:plan_id>/delete", methods=["POST"])
@login_required
def delete(plan_id: int):
    with db.conn() as c:
        c.execute("DELETE FROM plans WHERE id=?", (plan_id,))
    log.info("Deleted plan #%d", plan_id)
    return redirect(url_for('plans_panel.index') + '?ok=deleted')


@bp.route("/api/list")
@login_required
def api_list():
    now = int(time.time())
    with db.conn() as c:
        rows = c.execute(
            "SELECT * FROM plans WHERE is_active=1 ORDER BY price_pkr ASC"
        ).fetchall()
    result = []
    for p in rows:
        d = dict(p)
        try:
            d['features_list'] = json.loads(p['features_json'] or '[]')
        except Exception:
            d['features_list'] = []
        result.append(d)
    return jsonify({"plans": result})
