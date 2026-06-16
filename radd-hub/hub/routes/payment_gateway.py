"""Payment Gateway Admin Panel — control EasyPaisa/JazzCash/NayaPay/SadaPay."""
from __future__ import annotations
import time, json, logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required

log = logging.getLogger("hub.payment_gateway")
bp = Blueprint("payment_gateway", __name__, url_prefix="/billing")

_HTML = """
{% extends "base.html" %}
{% set active="billing" %}
{% block title %}Payment Gateway{% endblock %}
{% block content %}
<style>
.billing-page{max-width:1200px;margin:0 auto}
.billing-page h2{margin:0 0 4px}
.sub-sub{color:var(--muted);font-size:.85rem;margin-bottom:24px}
.stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:28px}
@media(max-width:700px){.stat-grid{grid-template-columns:repeat(2,1fr)}}
.s-tile{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:16px 18px}
.s-tile .k{font-size:.75rem;text-transform:uppercase;letter-spacing:.5px;color:var(--muted)}
.s-tile .v{font-size:2rem;font-weight:700;margin-top:4px}
/* Gateway cards */
.gw-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:18px;margin-bottom:28px}
.gw-card{background:var(--panel);border:1px solid var(--border);border-radius:14px;overflow:hidden;transition:box-shadow .15s}
.gw-card:hover{box-shadow:0 4px 20px #0004}
.gw-card.disabled{opacity:.6}
.gw-header{display:flex;align-items:center;justify-content:space-between;padding:18px 18px 14px}
.gw-info{display:flex;align-items:center;gap:12px}
.gw-icon{width:44px;height:44px;border-radius:12px;display:flex;align-items:center;justify-content:center;font-size:22px;background:var(--panel2);border:1px solid var(--border)}
.gw-title{font-size:16px;font-weight:700}
.gw-sub{font-size:11px;color:var(--muted);margin-top:2px}
.toggle-switch{position:relative;display:inline-block;width:46px;height:24px}
.toggle-switch input{opacity:0;width:0;height:0}
.toggle-slider{position:absolute;cursor:pointer;inset:0;background:var(--panel2);border:1px solid var(--border);border-radius:24px;transition:.2s}
.toggle-slider:before{content:"";position:absolute;height:18px;width:18px;left:2px;bottom:2px;background:var(--muted);border-radius:50%;transition:.2s}
.toggle-switch input:checked + .toggle-slider{background:var(--ok);border-color:var(--ok)}
.toggle-switch input:checked + .toggle-slider:before{transform:translateX(22px);background:#fff}
.gw-body{padding:0 18px 18px}
.gw-field{margin-bottom:10px}
.gw-field label{display:block;font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;margin-bottom:4px}
.gw-field input,.gw-field textarea{width:100%;padding:8px 11px;background:var(--panel2);border:1px solid var(--border);color:var(--text);border-radius:7px;font-size:13px;font-family:inherit}
.gw-field input:focus,.gw-field textarea:focus{outline:none;border-color:var(--accent)}
.gw-field textarea{resize:vertical;min-height:60px}
.gw-actions{display:flex;gap:8px;margin-top:14px}
.gw-save{flex:1;background:var(--accent);color:#fff;border:none;border-radius:7px;padding:8px;font-weight:600;font-size:13px;cursor:pointer}
.gw-save:hover{filter:brightness(1.1)}
/* SMS History */
.sms-table{background:var(--panel);border:1px solid var(--border);border-radius:12px;overflow:hidden;margin-bottom:28px}
.sms-table table{width:100%;border-collapse:collapse}
.sms-table th{background:var(--panel2);padding:10px 14px;font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;text-align:left}
.sms-table td{padding:10px 14px;font-size:12px;border-top:1px solid var(--border);vertical-align:middle}
/* Settings card */
.settings-card{background:var(--panel);border:1px solid var(--border);border-radius:14px;padding:22px;margin-bottom:28px}
.settings-card h3{margin:0 0 18px;font-size:15px;font-weight:600}
.form-2col{display:grid;grid-template-columns:1fr 1fr;gap:14px}
@media(max-width:600px){.form-2col{grid-template-columns:1fr}}
.form-row{margin-bottom:12px}
.form-row label{display:block;font-size:11px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px;margin-bottom:5px}
.form-row input,.form-row select{width:100%;padding:9px 12px;background:var(--panel2);border:1px solid var(--border);color:var(--text);border-radius:8px;font-size:13px;font-family:inherit}
.form-row input:focus{outline:none;border-color:var(--accent)}
.key-box{font-family:monospace;font-size:12px;background:var(--panel2);padding:10px 14px;border-radius:8px;border:1px solid var(--border);word-break:break-all;display:flex;align-items:center;gap:10px}
.key-box code{flex:1;color:var(--warn)}
.copy-btn{background:none;border:1px solid var(--border);color:var(--muted);border-radius:5px;padding:3px 8px;font-size:11px;cursor:pointer;white-space:nowrap}
.copy-btn:hover{background:var(--panel);color:var(--text);filter:none}
</style>

<div class="billing-page">
  <div class="h-row">
    <div>
      <h2>💳 Payment Gateway</h2>
      <p class="sub-sub">Manage payment methods, account numbers, and SMS auto-approval settings.</p>
    </div>
  </div>

  <div class="stat-grid">
    <div class="s-tile">
      <div class="k">SMS Received</div>
      <div class="v">{{ stats.total_sms }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Auto-Approved</div>
      <div class="v" style="color:var(--ok)">{{ stats.auto_approved }}</div>
    </div>
    <div class="s-tile">
      <div class="k">Pending TIDs</div>
      <div class="v" style="color:var(--warn)">{{ stats.pending_tids }}</div>
    </div>
    <div class="s-tile">
      <div class="k">This Month</div>
      <div class="v" style="color:var(--accent)">₨{{ "{:,}".format(stats.month_rev) }}</div>
    </div>
  </div>

  <!-- SMS Gateway Settings Card -->
  <div class="settings-card">
    <h3>⚙️ SMS Gateway Settings</h3>
    <div style="margin-bottom:14px">
      <div style="font-size:12px;color:var(--muted);margin-bottom:8px">Gateway Key (used by your admin phone app to POST incoming SMS):</div>
      <div class="key-box">
        <code id="gwKey">{{ gateway_key }}</code>
        <button class="copy-btn" onclick="copyKey()">Copy</button>
      </div>
    </div>
    <form id="smsSettingsForm" onsubmit="saveSmsSettings(event)">
    <div class="form-2col">
      <div class="form-row">
        <label>Amount Tolerance (PKR) — allow ±</label>
        <input type="number" name="sms_amount_tolerance_pkr" id="f_tolerance" min="0" step="1"
          value="{{ sms_settings.sms_amount_tolerance_pkr or 10 }}"
          placeholder="10">
      </div>
      <div class="form-row">
        <label>Auto-Approve SMS Payments</label>
        <select name="sms_auto_approve_enabled" id="f_auto_approve">
          <option value="1" {{ 'selected' if sms_settings.sms_auto_approve_enabled == '1' }}>Enabled</option>
          <option value="0" {{ 'selected' if sms_settings.sms_auto_approve_enabled != '1' }}>Disabled (manual only)</option>
        </select>
      </div>
    </div>
    <button type="submit">Save Settings</button>
    </form>
  </div>

  <h3 style="margin:0 0 16px;font-size:15px;font-weight:600">💰 Payment Methods</h3>
  <div class="gw-grid">
    {% for m in methods %}
    <div class="gw-card {% if not m.is_enabled %}disabled{% endif %}" id="card-{{ m.code }}">
      <div class="gw-header">
        <div class="gw-info">
          <div class="gw-icon">{{ m.icon }}</div>
          <div>
            <div class="gw-title">{{ m.name }}</div>
            <div class="gw-sub">{{ m.account_number or 'No account set' }}</div>
          </div>
        </div>
        <label class="toggle-switch" title="{{ 'Disable' if m.is_enabled else 'Enable' }}">
          <input type="checkbox" {{ 'checked' if m.is_enabled }}
            onchange="toggleMethod('{{ m.code }}', this.checked)">
          <span class="toggle-slider"></span>
        </label>
      </div>
      <div class="gw-body">
        <div class="gw-field">
          <label>Account Number / MSISDN</label>
          <input type="text" id="num-{{ m.code }}" value="{{ m.account_number or '' }}"
            placeholder="03001234567">
        </div>
        <div class="gw-field">
          <label>Account Name</label>
          <input type="text" id="name-{{ m.code }}" value="{{ m.account_name or '' }}"
            placeholder="Muhammad Radd">
        </div>
        <div class="gw-field">
          <label>Payment Instructions (shown in app)</label>
          <textarea id="instr-{{ m.code }}" rows="2" placeholder="How to send money...">{{ m.instructions or '' }}</textarea>
        </div>
        <div class="gw-field" style="display:grid;grid-template-columns:1fr 1fr;gap:10px">
          <div>
            <label>Min Amount (PKR)</label>
            <input type="number" id="min-{{ m.code }}" value="{{ m.min_amount_pkr|int }}" min="0">
          </div>
          <div>
            <label>Tolerance (PKR ±)</label>
            <input type="number" id="tol-{{ m.code }}" value="{{ m.amount_tolerance_pkr|int }}" min="0">
          </div>
        </div>
        <div class="gw-actions">
          <button class="gw-save" onclick="saveMethod('{{ m.code }}')">Save Changes</button>
        </div>
      </div>
    </div>
    {% endfor %}
  </div>

  <!-- Recent SMS Payments -->
  <div class="card">
    <div class="h-row" style="margin-bottom:12px">
      <h3 style="margin:0">📩 Recent SMS Payments</h3>
      <a href="/billing/sms-export" class="btn ghost" style="font-size:12px;padding:5px 12px">Export CSV</a>
    </div>
    {% if sms_payments %}
    <div class="table-wrap">
    <table>
      <thead><tr>
        <th>Time</th><th>Source</th><th>TID</th><th>Amount</th>
        <th>Sender</th><th>Matched</th><th>Status</th>
      </tr></thead>
      <tbody>
      {% for s in sms_payments %}
      <tr>
        <td style="color:var(--muted);white-space:nowrap">{{ s.received_human }}</td>
        <td><span class="badge b-info">{{ s.source|upper }}</span></td>
        <td style="font-family:monospace;font-size:11px">{{ s.tid }}</td>
        <td style="color:var(--ok);font-weight:600">₨{{ "{:,}".format(s.amount_pkr|int if s.amount_pkr else 0) }}</td>
        <td style="font-family:monospace;font-size:11px">{{ s.sender_phone or '—' }}</td>
        <td>{% if s.matched_payment_id %}<span class="badge b-ok">#{{ s.matched_payment_id }}</span>{% else %}<span class="badge b-mut">Unmatched</span>{% endif %}</td>
        <td>
          {% if s.matched_payment_id %}<span class="badge b-ok">Approved</span>
          {% else %}<span class="badge b-warn">Pending</span>{% endif %}
        </td>
      </tr>
      {% endfor %}
      </tbody>
    </table>
    </div>
    {% else %}
    <div class="empty">No SMS payments received yet.</div>
    {% endif %}
  </div>
</div>

<script>
async function toggleMethod(code, enabled){
  const card = document.getElementById('card-'+code);
  const r = await api('/billing/api/methods/'+code+'/toggle', {method:'POST', body:{enabled}});
  if(r.ok){
    card.classList.toggle('disabled', !enabled);
    toast(enabled ? code+' enabled' : code+' disabled');
  } else { toast('Error: '+(r.error||'unknown'), 4000); }
}
async function saveMethod(code){
  const body = {
    account_number: document.getElementById('num-'+code).value.trim(),
    account_name:   document.getElementById('name-'+code).value.trim(),
    instructions:   document.getElementById('instr-'+code).value.trim(),
    min_amount_pkr: parseFloat(document.getElementById('min-'+code).value)||0,
    amount_tolerance_pkr: parseFloat(document.getElementById('tol-'+code).value)||10,
  };
  const r = await api('/billing/api/methods/'+code, {method:'POST', body});
  if(r.ok){ toast(code+' saved ✓'); } else { toast('Error: '+(r.error||'unknown'), 4000); }
}
async function saveSmsSettings(e){
  e.preventDefault();
  const fd = new FormData(e.target);
  const body = Object.fromEntries(fd.entries());
  const r = await api('/billing/api/sms-settings', {method:'POST', body});
  if(r.ok) toast('Settings saved ✓'); else toast('Error: '+(r.error||'unknown'),4000);
}
function copyKey(){
  const k = document.getElementById('gwKey').textContent;
  navigator.clipboard.writeText(k).then(()=>toast('Gateway key copied!')).catch(()=>{
    const ta=document.createElement('textarea');ta.value=k;document.body.appendChild(ta);ta.select();document.execCommand('copy');document.body.removeChild(ta);toast('Copied!');
  });
}
</script>
{% endblock %}
"""

import datetime as _dt

def _fmt(ts):
    if not ts: return "—"
    return _dt.datetime.fromtimestamp(int(ts)).strftime("%d %b %H:%M")


@bp.route("/")
@login_required
def index():
    now = int(time.time())
    month_start = int(time.mktime(time.strptime(time.strftime("%Y-%m-01"), "%Y-%m-%d")))
    with db.conn() as c:
        methods = c.execute("SELECT * FROM payment_methods ORDER BY sort_order ASC").fetchall()
        total_sms    = c.execute("SELECT COUNT(*) AS n FROM received_sms_payments").fetchone()["n"]
        auto_approved= c.execute("SELECT COUNT(*) AS n FROM received_sms_payments WHERE matched_payment_id IS NOT NULL").fetchone()["n"]
        pending_tids = c.execute("SELECT COUNT(*) AS n FROM tid_payments WHERE status='pending'").fetchone()["n"]
        month_rev    = c.execute(
            "SELECT COALESCE(SUM(amount_pkr),0) AS v FROM tid_payments WHERE status='approved' AND submitted_at>=?",
            (month_start,)).fetchone()["v"] or 0
        sms_payments = c.execute(
            "SELECT * FROM received_sms_payments ORDER BY received_at DESC LIMIT 50"
        ).fetchall()
        gw_key_row = c.execute("SELECT v FROM settings WHERE k='sms_gateway_key'").fetchone()
        gateway_key = gw_key_row["v"] if gw_key_row else "not set"
        # SMS settings
        sms_settings = {}
        for k in ['sms_amount_tolerance_pkr','sms_auto_approve_enabled']:
            row = c.execute("SELECT v FROM settings WHERE k=?", (k,)).fetchone()
            sms_settings[k] = row["v"] if row else ("10" if "tolerance" in k else "1")

    sms_list = []
    for s in sms_payments:
        d = dict(s)
        d["received_human"] = _fmt(s["received_at"])
        sms_list.append(d)

    return render_template_string(_HTML,
        methods=[dict(m) for m in methods],
        stats={"total_sms":total_sms,"auto_approved":auto_approved,
               "pending_tids":pending_tids,"month_rev":int(month_rev)},
        sms_payments=sms_list,
        gateway_key=gateway_key,
        sms_settings=sms_settings)


@bp.route("/api/methods/<code>", methods=["POST"])
@login_required
def update_method(code: str):
    d = request.get_json(force=True, silent=True) or {}
    now = int(time.time())
    with db.conn() as c:
        c.execute("""UPDATE payment_methods SET
            account_number=?, account_name=?, instructions=?,
            min_amount_pkr=?, amount_tolerance_pkr=?, updated_at=?
            WHERE code=?""",
            (str(d.get("account_number","")).strip(),
             str(d.get("account_name","")).strip(),
             str(d.get("instructions","")).strip(),
             float(d.get("min_amount_pkr",0) or 0),
             float(d.get("amount_tolerance_pkr",10) or 10),
             now, code))
    log.info("Updated payment method: %s", code)
    return jsonify({"ok": True})


@bp.route("/api/methods/<code>/toggle", methods=["POST"])
@login_required
def toggle_method(code: str):
    d = request.get_json(force=True, silent=True) or {}
    enabled = 1 if d.get("enabled") else 0
    now = int(time.time())
    with db.conn() as c:
        c.execute("UPDATE payment_methods SET is_enabled=?, updated_at=? WHERE code=?",
                  (enabled, now, code))
    log.info("Payment method %s %s", code, "enabled" if enabled else "disabled")
    return jsonify({"ok": True, "enabled": bool(enabled)})


@bp.route("/api/sms-settings", methods=["POST"])
@login_required
def save_sms_settings():
    d = request.get_json(force=True, silent=True) or {}
    for k in ['sms_amount_tolerance_pkr','sms_auto_approve_enabled']:
        if k in d:
            with db.conn() as c:
                c.execute("INSERT OR REPLACE INTO settings(k,v) VALUES(?,?)", (k, str(d[k])))
    log.info("Updated SMS settings")
    return jsonify({"ok": True})


@bp.route("/sms-export")
@login_required
def sms_export():
    from flask import Response
    import csv, io
    with db.conn() as c:
        rows = c.execute("SELECT * FROM received_sms_payments ORDER BY received_at DESC").fetchall()
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(['ID','Source','TID','Amount PKR','Sender','Received At','Matched Payment ID'])
    for r in rows:
        w.writerow([r['id'],r['source'],r['tid'],r['amount_pkr'],r['sender_phone'],
                    _fmt(r['received_at']),r['matched_payment_id'] or ''])
    return Response(buf.getvalue(), mimetype='text/csv',
                    headers={'Content-Disposition':'attachment;filename=sms_payments.csv'})


# Public API for Flutter app — returns active payment methods
@bp.route("/api/public/methods")
def public_methods():
    with db.conn() as c:
        rows = c.execute(
            "SELECT code,name,account_number,account_name,instructions,icon FROM payment_methods WHERE is_enabled=1 ORDER BY sort_order ASC"
        ).fetchall()
    return jsonify({"methods": [dict(r) for r in rows]})
