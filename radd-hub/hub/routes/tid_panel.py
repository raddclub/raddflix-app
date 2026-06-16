"""TID Payment Verification Panel — admin UI in Radd Hub.

Routes:
  GET  /tid/              — list pending + recent TID payments
  POST /tid/<id>/approve  — approve payment, activate subscription
  POST /tid/<id>/reject   — reject payment with optional note
"""
from __future__ import annotations
import time
import logging
from flask import Blueprint, render_template_string, request, redirect, url_for, jsonify
from hub import db
from hub.auth import login_required, csrf_protect

log = logging.getLogger("hub.tid_panel")

bp = Blueprint("tid_panel", __name__, url_prefix="/tid")

PLAN_DURATIONS = {
    "basic":    30,
    "standard": 30,
    "premium":  30,
}

# Expected prices per plan (PKR). Used for SMS amount validation on manual approval.
PLAN_PRICES = {
    "basic":    149,
    "standard": 299,
    "premium":  499,
}
# Amount tolerance in PKR — allow minor rounding differences
AMOUNT_TOLERANCE = 5

_HTML = """
{% extends "base.html" %}
{% block title %}TID Payments{% endblock %}
{% block content %}
<style>
.tid-page { max-width: 960px; margin: 0 auto; padding: 24px 16px; }
.tid-page h1 { font-size: 1.4rem; margin-bottom: 4px; color: #e7eaf2; }
.tid-page .sub { color: #7e859b; font-size: .85rem; margin-bottom: 24px; }
.tabs { display: flex; gap: 8px; margin-bottom: 20px; flex-wrap: wrap; }
.tab-btn {
  padding: 6px 16px; border-radius: 8px; border: 1px solid #252d3d;
  background: #12151e; color: #7e859b; cursor: pointer; font-size: .85rem;
  text-decoration: none;
}
.tab-btn.active { background: #E8002D; color: #fff; border-color: #E8002D; }
.tab-btn.sms-tab.active { background: #1565C0; border-color: #1565C0; }
.card {
  background: #12151e; border: 1px solid #252d3d; border-radius: 12px;
  padding: 16px 20px; margin-bottom: 12px;
}
.card-top { display: flex; align-items: center; gap: 12px; flex-wrap: wrap; }
.badge { padding: 3px 10px; border-radius: 20px; font-size: .75rem; font-weight: 600; }
.badge-pending  { background: rgba(255,193,7,.15);  color: #ffc107; }
.badge-approved { background: rgba(0,230,118,.15);  color: #00e676; }
.badge-rejected { background: rgba(255,107,107,.15); color: #ff6b6b; }
.badge-matched   { background: rgba(0,230,118,.15);  color: #00e676; }
.badge-unmatched { background: rgba(255,193,7,.15);  color: #ffc107; }
.plan-tag {
  padding: 3px 10px; border-radius: 20px; font-size: .75rem; font-weight: 700;
  background: rgba(232,0,45,.15); color: #E8002D;
}
.source-jc { background: rgba(232,0,45,.15); color: #E8002D; padding: 3px 10px; border-radius: 20px; font-size: .75rem; font-weight: 700; }
.source-ep { background: rgba(21,101,192,.15); color: #5cb4ff; padding: 3px 10px; border-radius: 20px; font-size: .75rem; font-weight: 700; }
.card-meta { font-size: .82rem; color: #7e859b; margin-top: 8px; }
.card-meta span { margin-right: 18px; }
.tid-val { font-family: monospace; font-size: .95rem; color: #e7eaf2; font-weight: 600; }
.actions { display: flex; gap: 8px; margin-top: 12px; }
.btn-approve {
  padding: 7px 18px; background: #00e676; color: #000; border: none;
  border-radius: 8px; font-weight: 700; cursor: pointer; font-size: .85rem;
}
.btn-reject {
  padding: 7px 18px; background: transparent; color: #ff6b6b;
  border: 1px solid #ff6b6b; border-radius: 8px; cursor: pointer; font-size: .85rem;
}
.note-input {
  margin-top: 8px; width: 100%; padding: 8px 10px;
  background: #181d28; border: 1px solid #252d3d; color: #e7eaf2;
  border-radius: 8px; font-size: .85rem;
}
.empty { text-align: center; color: #7e859b; padding: 40px; font-size: .9rem; }
.amount { font-size: 1.1rem; font-weight: 700; color: #00e676; }
.warn-no-user {
  background: rgba(255,193,7,.1); border: 1px solid rgba(255,193,7,.3);
  border-radius: 8px; padding: 6px 12px; font-size: .8rem; color: #ffc107;
  margin-top: 6px;
}
.sms-stats { display: grid; grid-template-columns: repeat(3,1fr); gap: 12px; margin-bottom: 20px; }
.sms-stat { background: #181d28; border: 1px solid #252d3d; border-radius: 10px; padding: 14px 16px; }
.sms-stat .k { font-size: .75rem; text-transform: uppercase; letter-spacing: .5px; color: #7e859b; }
.sms-stat .v { font-size: 1.8rem; font-weight: 700; margin-top: 4px; }
.raw-sms { font-size: .78rem; color: #7e859b; background: #0a0c11; border-radius: 6px; padding: 8px 10px; margin-top: 8px; font-family: monospace; word-break: break-word; }
</style>

<div class="tid-page">
  <h1>💳 TID Payment Verification</h1>
  <p class="sub">Manually verify JazzCash / Easypaisa Transaction IDs and activate subscriptions.</p>

  <!-- SMS Gateway Key -->
  <div style="background:#0a1628;border:1px solid #1e3a5f;border-radius:12px;padding:16px 20px;margin-bottom:20px">
    <div style="display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <span style="font-size:1rem;font-weight:700;color:#e7eaf2">📱 SMS Gateway Key</span>
      <span style="font-size:.8rem;color:#7e859b">Copy into JazzPay Monitor → Config → Gateway Key</span>
    </div>
    <div style="margin-top:10px;display:flex;align-items:center;gap:10px;flex-wrap:wrap">
      <code id="gw-key" style="font-family:monospace;background:#12151e;padding:8px 14px;border-radius:8px;border:1px solid #252d3d;color:#00e676;font-size:.85rem;word-break:break-all">{{ gateway_key }}</code>
      <button onclick="navigator.clipboard.writeText(document.getElementById('gw-key').innerText).then(()=>{this.innerText='Copied!';setTimeout(()=>this.innerText='Copy',2000)})" style="padding:6px 14px;background:#1e3a5f;border:none;border-radius:8px;color:#7eb8f7;cursor:pointer;font-size:.8rem">Copy</button>
    </div>
  </div>

  <div class="tabs">
    <a href="?tab=pending"  class="tab-btn {% if tab=='pending' %}active{% endif %}">
      Pending {% if pending_count %}<span style="background:#E8002D;border-radius:10px;padding:1px 7px;font-size:.75rem;margin-left:4px">{{ pending_count }}</span>{% endif %}
    </a>
    <a href="?tab=approved" class="tab-btn {% if tab=='approved' %}active{% endif %}">Approved</a>
    <a href="?tab=rejected" class="tab-btn {% if tab=='rejected' %}active{% endif %}">Rejected</a>
    <a href="?tab=all"      class="tab-btn {% if tab=='all' %}active{% endif %}">All</a>
    <a href="?tab=sms"      class="tab-btn sms-tab {% if tab=='sms' %}active{% endif %}">
      📲 SMS Received {% if sms_unmatched %}<span style="background:#1565C0;border-radius:10px;padding:1px 7px;font-size:.75rem;margin-left:4px">{{ sms_unmatched }}</span>{% endif %}
    </a>
  </div>

  <!-- ── SMS PAYMENTS TAB ── -->
  {% if tab == 'sms' %}
    <div class="sms-stats">
      <div class="sms-stat"><div class="k">Total Received</div><div class="v" style="color:#5cb4ff">{{ sms_total }}</div></div>
      <div class="sms-stat"><div class="k">Auto-Approved</div><div class="v" style="color:#00e676">{{ sms_matched }}</div></div>
      <div class="sms-stat"><div class="k">Waiting for User</div><div class="v" style="color:#ffc107">{{ sms_unmatched }}</div></div>
    </div>

    {% if not sms_payments %}
      <div class="empty">No SMS payments received yet.<br><span style="font-size:.8rem">Install JazzPay Monitor on your phone and enable SMS monitoring.</span></div>
    {% endif %}

    {% for s in sms_payments %}
    <div class="card">
      <div class="card-top">
        {% if s.source == 'jazzcash' %}
          <span class="source-jc">JazzCash</span>
        {% else %}
          <span class="source-ep">EasyPaisa</span>
        {% endif %}
        {% if s.matched_payment_id %}
          <span class="badge badge-matched">✓ Auto-Approved</span>
        {% else %}
          <span class="badge badge-unmatched">⏳ Waiting for user TID submit</span>
        {% endif %}
        {% if s.amount_pkr %}<span class="amount">PKR {{ s.amount_pkr }}</span>{% endif %}
        {% if s.sender_phone %}<span style="color:#7e859b;font-size:.8rem">from {{ s.sender_phone }}</span>{% endif %}
      </div>
      <div class="card-meta">
        <span>TID: <span class="tid-val">{{ s.tid }}</span></span>
        <span>received {{ s.received_human }}</span>
        {% if s.matched_payment_id %}<span style="color:#00e676">→ TID Payment #{{ s.matched_payment_id }}</span>{% endif %}
      </div>
      {% if s.raw_sms %}
      <div class="raw-sms">{{ s.raw_sms }}</div>
      {% endif %}
    </div>
    {% endfor %}

  <!-- ── TID PAYMENTS TABS ── -->
  {% else %}
    {% if not payments %}
      <div class="empty">No {{ tab }} payments found.</div>
    {% endif %}

    {% for p in payments %}
    <div class="card">
      <div class="card-top">
        <span class="badge badge-{{ p.status }}">{{ p.status.upper() }}</span>
        <span class="plan-tag">{{ p.plan.upper() }}</span>
        <span class="amount">PKR {{ p.amount_pkr }}</span>
        <span style="color:#e7eaf2;font-size:.9rem">📱 {{ p.phone }}</span>
        {% if p.user_id %}<span style="color:#7e859b;font-size:.8rem">UID: {{ p.user_id }}</span>{% else %}<span style="color:#ffc107;font-size:.8rem">⚠ No account linked yet</span>{% endif %}
      </div>
      <div class="card-meta">
        <span>TID: <span class="tid-val">{{ p.tid }}</span></span>
        <span>via {{ p.payment_method | upper }}</span>
        <span>submitted {{ p.submitted_human }}</span>
        {% if p.reviewed_at %}<span>reviewed {{ p.reviewed_human }}</span>{% endif %}
        {% if p.admin_note %}<span style="color:#ffc107">Note: {{ p.admin_note }}</span>{% endif %}
      </div>
      {% if not p.user_id and p.status == 'pending' %}
      <div class="warn-no-user">
        ⚠ User submitted before creating an account. If they register with <strong>{{ p.phone }}</strong>, the subscription will activate automatically on approval.
      </div>
      {% endif %}

      {% if p.status == 'pending' %}
      <div class="actions">
        <form method="post" action="/tid/{{ p.id }}/approve" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="hidden" name="_csrf_token" value="{{ csrf_token() }}">
          <button class="btn-approve" type="submit">✓ Approve & Activate</button>
          <input class="note-input" name="note" placeholder="Optional note for records..." style="width:240px">
        </form>
        <form method="post" action="/tid/{{ p.id }}/reject" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap"><input type="hidden" name="_csrf_token" value="{{ csrf_token() }}">
          <input class="note-input" name="note" placeholder="Reason for rejection..." style="width:200px">
          <button class="btn-reject" type="submit">✗ Reject</button>
        </form>
      </div>
      {% endif %}
    </div>
    {% endfor %}
  {% endif %}

</div>
{% endblock %}
"""

def _fmt_time(ts):
    if not ts:
        return "—"
    import datetime
    return datetime.datetime.fromtimestamp(int(ts)).strftime("%d %b %Y, %H:%M")


@bp.route("/")
@login_required
def index():
    tab = request.args.get("tab", "pending")

    with db.conn() as c:
        pending_count = c.execute(
            "SELECT COUNT(*) AS n FROM tid_payments WHERE status='pending'"
        ).fetchone()["n"]

        gk_row = c.execute("SELECT v FROM settings WHERE k='sms_gateway_key'").fetchone()
        gateway_key = gk_row["v"] if gk_row else "(not set)"

    # ── SMS tab ──────────────────────────────────────────────────────────────
    if tab == "sms":
        with db.conn() as c:
            sms_rows = c.execute(
                "SELECT * FROM received_sms_payments ORDER BY received_at DESC LIMIT 100"
            ).fetchall()
            sms_total     = c.execute("SELECT COUNT(*) AS n FROM received_sms_payments").fetchone()["n"]
            sms_matched   = c.execute("SELECT COUNT(*) AS n FROM received_sms_payments WHERE matched_payment_id IS NOT NULL").fetchone()["n"]
            sms_unmatched = sms_total - sms_matched

        sms_payments = []
        for r in sms_rows:
            d = dict(r)
            d["received_human"] = _fmt_time(r["received_at"])
            sms_payments.append(d)

        return render_template_string(_HTML,
            tab=tab,
            payments=[],
            pending_count=pending_count,
            gateway_key=gateway_key,
            sms_payments=sms_payments,
            sms_total=sms_total,
            sms_matched=sms_matched,
            sms_unmatched=sms_unmatched,
        )

    # ── TID tabs ─────────────────────────────────────────────────────────────
    status_filter = {
        "pending":  "pending",
        "approved": "approved",
        "rejected": "rejected",
        "all":      None,
    }.get(tab, "pending")

    with db.conn() as c:
        if status_filter:
            rows = c.execute(
                "SELECT * FROM tid_payments WHERE status=? ORDER BY submitted_at DESC LIMIT 100",
                (status_filter,)
            ).fetchall()
        else:
            rows = c.execute(
                "SELECT * FROM tid_payments ORDER BY submitted_at DESC LIMIT 100"
            ).fetchall()

    payments = []
    for r in rows:
        d = dict(r)
        d["submitted_human"] = _fmt_time(r["submitted_at"])
        d["reviewed_human"]  = _fmt_time(r["reviewed_at"])
        payments.append(d)

    # sms_unmatched for badge on tab even when not on sms tab
    with db.conn() as c:
        sms_total     = c.execute("SELECT COUNT(*) AS n FROM received_sms_payments").fetchone()["n"]
        sms_matched   = c.execute("SELECT COUNT(*) AS n FROM received_sms_payments WHERE matched_payment_id IS NOT NULL").fetchone()["n"]
        sms_unmatched = sms_total - sms_matched

    return render_template_string(_HTML,
        payments=payments,
        tab=tab,
        pending_count=pending_count,
        gateway_key=gateway_key,
        sms_payments=[],
        sms_total=sms_total,
        sms_matched=sms_matched,
        sms_unmatched=sms_unmatched,
    )


@bp.route("/<int:payment_id>/approve", methods=["POST"])
@login_required
@csrf_protect
def approve(payment_id: int):
    note = (request.form.get("note") or "").strip()
    now  = int(time.time())

    # TID replay protection: check inside transaction to prevent double-approval
    with db.conn() as c:
        payment = c.execute(
            "SELECT * FROM tid_payments WHERE id=? AND status='pending'", (payment_id,)
        ).fetchone()

    if not payment:
        # Either not found OR already approved/rejected (replay blocked)
        log.warning("TID approve replay attempt or not found: payment_id=%s", payment_id)
        return redirect(url_for("tid_panel.index", tab="all"))

    plan          = payment["plan"]
    user_id       = payment["user_id"]
    phone         = payment["phone"]
    duration_days = PLAN_DURATIONS.get(plan, 30)

    # ── SMS Amount validation ───────────────────────────────────────────────
    # If the admin hasn't force-confirmed, warn them if amount doesn't match plan price.
    amount_pkr    = dict(payment).get("amount_pkr")
    expected_price = PLAN_PRICES.get(plan)
    force_approve  = request.form.get("force_approve") == "1"
    if (not force_approve and amount_pkr is not None and expected_price is not None):
        try:
            paid = float(amount_pkr)
            if abs(paid - expected_price) > AMOUNT_TOLERANCE:
                log.warning(
                    "TID %s amount mismatch: paid=%.0f expected=%.0f plan=%s — admin must force-confirm",
                    payment["tid"], paid, expected_price, plan
                )
                # Return warning page — admin must confirm
                _warn_html = f"""
                <html><head><style>
                body{{background:#0a0c11;color:#e7eaf2;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0}}
                .box{{background:#12151e;border:1px solid #ff6b6b;border-radius:14px;padding:32px;max-width:440px;width:90%}}
                h2{{color:#ff6b6b;margin:0 0 12px}} p{{color:#9ca3af;margin:0 0 20px;line-height:1.6}}
                .amt{{font-size:1.5rem;font-weight:700}} .exp{{color:#7e859b}}
                .btn-confirm{{background:#ff6b6b;color:#000;border:none;padding:10px 24px;border-radius:8px;font-weight:700;cursor:pointer;font-size:.9rem;margin-right:8px}}
                .btn-cancel{{background:transparent;color:#7e859b;border:1px solid #252d3d;padding:10px 24px;border-radius:8px;cursor:pointer;font-size:.9rem}}
                </style></head><body><div class="box">
                <h2>⚠ Amount Mismatch</h2>
                <p>TID <code style="color:#e7eaf2">{payment['tid']}</code><br>
                <span class="amt" style="color:#ff6b6b">PKR {int(paid):,}</span> paid — 
                <span class="exp">PKR {int(expected_price):,} expected for <strong>{plan.upper()}</strong></span></p>
                <p>This could indicate a wrong plan selection or partial payment. Approve anyway?</p>
                <form method="post" action="/tid/{payment_id}/approve">
                  <input type="hidden" name="_csrf_token" value="{request.form.get('_csrf_token', '')}">
                  <input type="hidden" name="note" value="{note}">
                  <input type="hidden" name="force_approve" value="1">
                  <button class="btn-confirm" type="submit">Force Approve</button>
                  <a href="/tid/?tab=pending"><button class="btn-cancel" type="button">Cancel</button></a>
                </form>
                </div></body></html>"""
                from flask import Response
                return Response(_warn_html, status=200, mimetype='text/html')
        except (TypeError, ValueError):
            pass
    started_at    = now
    expires_at    = now + duration_days * 86400

    if not user_id and phone:
        with db.conn() as c:
            user_row = c.execute(
                "SELECT id FROM app_users WHERE phone=?", (phone,)
            ).fetchone()
            if user_row:
                user_id = user_row["id"]
                c.execute(
                    "UPDATE tid_payments SET user_id=? WHERE id=?",
                    (user_id, payment_id)
                )
                log.info("TID %s: linked to user_id=%s via phone=%s", payment["tid"], user_id, phone)

    with db.conn() as c:
        c.execute(
            "UPDATE tid_payments SET status='approved', admin_note=?, reviewed_at=? WHERE id=?",
            (note or None, now, payment_id)
        )
        if user_id:
            c.execute(
                "UPDATE app_subscriptions SET is_active=0 WHERE user_id=?", (user_id,)
            )
            c.execute(
                """INSERT INTO app_subscriptions
                   (user_id, plan, started_at, expires_at, is_active, created_at)
                   VALUES (?,?,?,?,1,?)""",
                (user_id, plan, started_at, expires_at, now)
            )
            log.info("TID %s approved: user=%s plan=%s expires=%s", payment["tid"], user_id, plan, expires_at)
        else:
            log.warning(
                "TID %s approved but no app_users account found for phone=%s — "
                "subscription NOT activated.",
                payment["tid"], phone
            )

    return redirect(url_for("tid_panel.index", tab="pending"))


@bp.route("/<int:payment_id>/reject", methods=["POST"])
@login_required
@csrf_protect
def reject(payment_id: int):
    note = (request.form.get("note") or "").strip()
    now  = int(time.time())

    with db.conn() as c:
        c.execute(
            "UPDATE tid_payments SET status='rejected', admin_note=?, reviewed_at=? WHERE id=?",
            (note or None, now, payment_id)
        )

    return redirect(url_for("tid_panel.index", tab="pending"))
