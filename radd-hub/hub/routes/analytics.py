"""Analytics Panel — revenue, user growth, plan distribution, top content."""
from __future__ import annotations
import time, datetime, logging
from flask import Blueprint, render_template_string
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.analytics")
bp = Blueprint("analytics", __name__, url_prefix="/analytics")

_HTML = """
{% extends "base.html" %}
{% set active="analytics" %}
{% block title %}Analytics{% endblock %}
{% block content %}
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
.an-page { max-width: 1100px; margin: 0 auto; }
.an-page h2 { margin: 0 0 4px; }
.an-sub { color: var(--muted); font-size: .85rem; margin-bottom: 24px; }
.stat-grid { display: grid; grid-template-columns: repeat(4,1fr); gap: 14px; margin-bottom: 24px; }
@media(max-width:700px){ .stat-grid { grid-template-columns: repeat(2,1fr); } }
.s-tile { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 16px 18px; }
.s-tile .k { font-size: .75rem; text-transform: uppercase; letter-spacing: .5px; color: var(--muted); }
.s-tile .v { font-size: 2rem; font-weight: 700; margin-top: 4px; }
.s-tile .ch { font-size: .8rem; margin-top: 4px; }
.ch-green { color: var(--ok); } .ch-red { color: var(--err); } .ch-muted { color: var(--muted); }
.charts-row { display: grid; grid-template-columns: 2fr 1fr; gap: 14px; margin-bottom: 16px; }
@media(max-width:800px){ .charts-row { grid-template-columns: 1fr; } }
.chart-card { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 18px; }
.chart-card h3 { margin: 0 0 14px; font-size: 14px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
.table-card { background: var(--panel); border: 1px solid var(--border); border-radius: 12px; padding: 18px; margin-bottom: 14px; }
.table-card h3 { margin: 0 0 14px; font-size: 14px; color: var(--muted); text-transform: uppercase; letter-spacing: .5px; }
.plan-row { display: flex; align-items: center; gap: 10px; padding: 8px 0; border-bottom: 1px solid var(--border); }
.plan-row:last-child { border-bottom: none; }
.plan-bar { height: 8px; border-radius: 4px; flex: 1; background: var(--border); overflow: hidden; }
.plan-fill { height: 100%; border-radius: 4px; transition: width .4s; }
.empty-msg { text-align: center; color: var(--muted); padding: 30px; font-size: .9rem; }
</style>

<div class="an-page">
  <h2>📊 Analytics</h2>
  <p class="an-sub">Revenue, users, and content performance at a glance.</p>

  <!-- Stat tiles -->
  <div class="stat-grid">
    <div class="s-tile">
      <div class="k">Total Revenue</div>
      <div class="v" style="color:var(--ok)">PKR {{ total_revenue }}</div>
      <div class="ch ch-green">{{ approved_tids }} approved payments</div>
    </div>
    <div class="s-tile">
      <div class="k">Total Users</div>
      <div class="v" style="color:var(--blue)">{{ total_users }}</div>
      <div class="ch ch-green">+{{ new_users_7d }} last 7 days</div>
    </div>
    <div class="s-tile">
      <div class="k">Active Subs</div>
      <div class="v" style="color:var(--accent)">{{ active_subs }}</div>
      <div class="ch {% if expiring_7d > 0 %}ch-red{% else %}ch-muted{% endif %}">{{ expiring_7d }} expiring in 7d</div>
    </div>
    <div class="s-tile">
      <div class="k">Catalog</div>
      <div class="v">{{ total_titles }}</div>
      <div class="ch ch-muted">{{ free_titles }} free · {{ paid_titles }} paid</div>
    </div>
  </div>

  <div class="charts-row">
    <!-- Revenue chart (last 14 days) -->
    <div class="chart-card">
      <h3>Revenue — Last 14 Days</h3>
      {% if revenue_days %}
        <canvas id="revenueChart" height="120"></canvas>
      {% else %}
        <div class="empty-msg">No revenue data yet.</div>
      {% endif %}
    </div>
    <!-- Plan distribution -->
    <div class="chart-card">
      <h3>Plan Distribution</h3>
      {% if plan_dist %}
        <canvas id="planChart" height="180"></canvas>
      {% else %}
        <div class="empty-msg">No subscribers yet.</div>
      {% endif %}
    </div>
  </div>

  <!-- User growth chart -->
  <div class="chart-card" style="margin-bottom:14px">
    <h3>User Signups — Last 30 Days</h3>
    {% if signup_days %}
      <canvas id="signupChart" height="80"></canvas>
    {% else %}
      <div class="empty-msg">No signup data yet.</div>
    {% endif %}
  </div>

  <div class="charts-row">
    <!-- Top content -->
    <div class="table-card">
      <h3>🎬 Most Watched Titles</h3>
      {% if top_titles %}
        <table style="width:100%;border-collapse:collapse">
          <thead><tr>
            <th style="text-align:left;padding:6px 8px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">#</th>
            <th style="text-align:left;padding:6px 8px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Title</th>
            <th style="text-align:right;padding:6px 8px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Plays</th>
          </tr></thead>
          <tbody>
          {% for i, row in top_titles %}
          <tr>
            <td style="padding:8px;color:var(--muted);font-size:13px">{{ i }}</td>
            <td style="padding:8px;font-size:13px">{{ row.title }}</td>
            <td style="padding:8px;text-align:right;font-weight:700;color:var(--ok)">{{ row.plays }}</td>
          </tr>
          {% endfor %}
          </tbody>
        </table>
      {% else %}
        <div class="empty-msg">No watch history yet.</div>
      {% endif %}
    </div>

    <!-- Plan breakdown bars -->
    <div class="table-card">
      <h3>📋 Subscription Breakdown</h3>
      {% set plan_colors = {'basic':'#E8002D','standard':'#7c5cff','premium':'#00C853','free':'#7e859b'} %}
      {% if plan_dist %}
        {% set total_s = plan_dist | sum(attribute='count') %}
        {% for p in plan_dist %}
        <div class="plan-row">
          <span style="width:70px;font-size:13px;color:{{ plan_colors.get(p.plan,'#7e859b') }};font-weight:600">{{ p.plan | upper }}</span>
          <div class="plan-bar">
            <div class="plan-fill" style="width:{{ (p.count / total_s * 100)|int }}%;background:{{ plan_colors.get(p.plan,'#7e859b') }}"></div>
          </div>
          <span style="font-size:13px;font-weight:700;min-width:24px;text-align:right">{{ p.count }}</span>
        </div>
        {% endfor %}
      {% else %}
        <div class="empty-msg">No subscribers yet.</div>
      {% endif %}

      <div style="margin-top:20px;padding-top:14px;border-top:1px solid var(--border)">
        <h3 style="margin:0 0 10px">💰 Payment Methods</h3>
        {% for pm in payment_methods %}
        <div class="plan-row">
          <span style="width:90px;font-size:13px;color:var(--text)">{{ pm.method | upper }}</span>
          <div class="plan-bar">
            <div class="plan-fill" style="width:{{ (pm.count / (payment_methods | sum(attribute='count')) * 100)|int if payment_methods else 0 }}%;background:var(--accent)"></div>
          </div>
          <span style="font-size:13px;font-weight:700">{{ pm.count }}</span>
        </div>
        {% endfor %}
        {% if not payment_methods %}<div class="ch-muted" style="font-size:.85rem">No payments yet.</div>{% endif %}
      </div>
    </div>
  </div>

  <!-- Recent signups table -->
  <div class="table-card">
    <h3>👤 Recent Signups (Last 10)</h3>
    {% if recent_signups %}
    <div style="overflow-x:auto">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr>
          <th style="text-align:left;padding:7px 10px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Phone</th>
          <th style="text-align:left;padding:7px 10px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Name</th>
          <th style="text-align:left;padding:7px 10px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Plan</th>
          <th style="text-align:left;padding:7px 10px;font-size:11px;color:var(--muted);border-bottom:1px solid var(--border)">Joined</th>
        </tr></thead>
        <tbody>
        {% for u in recent_signups %}
        <tr>
          <td style="padding:8px 10px;font-family:monospace;font-size:13px">{{ u.phone }}</td>
          <td style="padding:8px 10px;font-size:13px">{{ u.name or '—' }}</td>
          <td style="padding:8px 10px">
            <span style="padding:2px 8px;border-radius:10px;font-size:12px;font-weight:700;
              background:{% if u.plan=='premium' %}rgba(0,200,83,.15){% elif u.plan=='basic' or u.plan=='standard' %}rgba(232,0,45,.15){% else %}rgba(126,133,155,.15){% endif %};
              color:{% if u.plan=='premium' %}var(--ok){% elif u.plan=='basic' or u.plan=='standard' %}#E8002D{% else %}var(--muted){% endif %}">
              {{ (u.plan or 'free') | upper }}
            </span>
          </td>
          <td style="padding:8px 10px;font-size:12px;color:var(--muted)">{{ u.joined }}</td>
        </tr>
        {% endfor %}
        </tbody>
      </table>
    </div>
    {% else %}
      <div class="empty-msg">No users yet.</div>
    {% endif %}
  </div>
</div>

{% block scripts %}
<script>
const CHART_DEFAULTS = {
  plugins: { legend: { labels: { color: '#e7eaf2', font: { size: 12 } } } },
  scales: {
    x: { ticks: { color: '#7e859b', font: { size: 11 } }, grid: { color: '#252d3d' } },
    y: { ticks: { color: '#7e859b', font: { size: 11 } }, grid: { color: '#252d3d' }, beginAtZero: true }
  }
};

{% if revenue_days %}
new Chart(document.getElementById('revenueChart'), {
  type: 'bar',
  data: {
    labels: {{ revenue_days | map(attribute='label') | list | tojson }},
    datasets: [{
      label: 'Revenue (PKR)',
      data: {{ revenue_days | map(attribute='amount') | list | tojson }},
      backgroundColor: 'rgba(0,200,83,0.6)',
      borderColor: '#00C853',
      borderWidth: 1,
      borderRadius: 4,
    }]
  },
  options: { ...CHART_DEFAULTS, plugins: { legend: { display: false } } }
});
{% endif %}

{% if signup_days %}
new Chart(document.getElementById('signupChart'), {
  type: 'line',
  data: {
    labels: {{ signup_days | map(attribute='label') | list | tojson }},
    datasets: [{
      label: 'New Users',
      data: {{ signup_days | map(attribute='count') | list | tojson }},
      borderColor: '#5cb4ff',
      backgroundColor: 'rgba(92,180,255,0.1)',
      tension: 0.4,
      fill: true,
      pointRadius: 3,
    }]
  },
  options: { ...CHART_DEFAULTS, plugins: { legend: { display: false } } }
});
{% endif %}

{% if plan_dist %}
new Chart(document.getElementById('planChart'), {
  type: 'doughnut',
  data: {
    labels: {{ plan_dist | map(attribute='plan') | list | tojson }},
    datasets: [{
      data: {{ plan_dist | map(attribute='count') | list | tojson }},
      backgroundColor: ['#E8002D','#7c5cff','#00C853','#7e859b'],
      borderWidth: 2,
      borderColor: '#12151e',
    }]
  },
  options: {
    plugins: { legend: { position: 'bottom', labels: { color: '#e7eaf2', font: { size: 12 }, padding: 12 } } },
    cutout: '60%',
  }
});
{% endif %}
</script>
{% endblock %}
{% endblock %}
"""

def _days_ago(n):
    now = datetime.datetime.now()
    return [(now - datetime.timedelta(days=i)).strftime("%Y-%m-%d") for i in range(n-1, -1, -1)]

@bp.route("/")
@login_required
def index():
    now = int(time.time())
    seven_days_ago  = now - 7  * 86400
    thirty_days_ago = now - 30 * 86400
    fourteen_days_ago = now - 14 * 86400

    with db.conn() as c:
        total_users    = c.execute("SELECT COUNT(*) AS n FROM app_users").fetchone()["n"]
        new_users_7d   = c.execute("SELECT COUNT(*) AS n FROM app_users WHERE created_at > ?", (seven_days_ago,)).fetchone()["n"]
        active_subs    = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at > ?", (now,)).fetchone()["n"]
        expiring_7d    = c.execute("SELECT COUNT(*) AS n FROM app_subscriptions WHERE is_active=1 AND expires_at BETWEEN ? AND ?", (now, now + 7*86400)).fetchone()["n"]
        total_titles   = c.execute("SELECT COUNT(*) AS n FROM titles").fetchone()["n"]
        free_titles    = c.execute("SELECT COUNT(*) AS n FROM titles WHERE is_free=1").fetchone()["n"]
        approved_tids  = c.execute("SELECT COUNT(*) AS n FROM tid_payments WHERE status='approved'").fetchone()["n"]
        total_revenue  = c.execute("SELECT COALESCE(SUM(amount_pkr),0) AS v FROM tid_payments WHERE status='approved'").fetchone()["v"]

        # Plan distribution
        plan_rows = c.execute("""
            SELECT COALESCE(s.plan,'free') as plan, COUNT(*) as count
            FROM app_users u
            LEFT JOIN app_subscriptions s ON s.user_id=u.id AND s.is_active=1
            GROUP BY plan ORDER BY count DESC
        """).fetchall()

        # Payment methods
        pm_rows = c.execute("""
            SELECT payment_method as method, COUNT(*) as count
            FROM tid_payments WHERE status='approved'
            GROUP BY payment_method ORDER BY count DESC
        """).fetchall()

        # Revenue by day (last 14 days)
        rev_rows = c.execute("""
            SELECT DATE(reviewed_at,'unixepoch') as day, SUM(amount_pkr) as amount
            FROM tid_payments WHERE status='approved' AND reviewed_at > ?
            GROUP BY day ORDER BY day
        """, (fourteen_days_ago,)).fetchall()

        # Signups by day (last 30 days)
        sig_rows = c.execute("""
            SELECT DATE(created_at,'unixepoch') as day, COUNT(*) as count
            FROM app_users WHERE created_at > ?
            GROUP BY day ORDER BY day
        """, (thirty_days_ago,)).fetchall()

        # Top titles by watch events (try/except: schema varies between server versions)
        try:
            top_rows = c.execute("""
                SELECT t.title, COUNT(*) as plays
                FROM watch_history wh
                JOIN files f ON f.id=CAST(wh.file_id AS INTEGER)
                JOIN titles t ON t.id=f.title_id
                GROUP BY t.id ORDER BY plays DESC LIMIT 10
            """).fetchall()
        except Exception:
            top_rows = []

        # Recent signups
        sig_users = c.execute("""
            SELECT u.phone, NULL as name,
                   COALESCE(s.plan,'free') as plan,
                   DATE(u.created_at,'unixepoch') as joined
            FROM app_users u
            LEFT JOIN app_subscriptions s ON s.user_id=u.id AND s.is_active=1
            ORDER BY u.created_at DESC LIMIT 10
        """).fetchall()

    # Build day-by-day revenue series (fill zeros for missing days)
    rev_map = {r["day"]: r["amount"] for r in rev_rows}
    revenue_days = []
    for d in _days_ago(14):
        revenue_days.append({"label": d[5:], "amount": rev_map.get(d, 0)})

    # Signup series
    sig_map = {r["day"]: r["count"] for r in sig_rows}
    signup_days = []
    for d in _days_ago(30):
        signup_days.append({"label": d[5:], "count": sig_map.get(d, 0)})

    return render_template_string(_HTML,
        total_revenue=int(total_revenue),
        total_users=total_users,
        new_users_7d=new_users_7d,
        active_subs=active_subs,
        expiring_7d=expiring_7d,
        total_titles=total_titles,
        free_titles=free_titles,
        paid_titles=total_titles - free_titles,
        approved_tids=approved_tids,
        plan_dist=[dict(r) for r in plan_rows],
        payment_methods=[dict(r) for r in pm_rows],
        revenue_days=revenue_days,
        signup_days=signup_days,
        top_titles=list(enumerate([dict(r) for r in top_rows], 1)),
        recent_signups=[dict(r) for r in sig_users],
    )
