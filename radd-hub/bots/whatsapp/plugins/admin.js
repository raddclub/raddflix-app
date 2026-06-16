'use strict';
const fs   = require('fs');
const path = require('path');
const fmt   = require('../lib/format');
const db    = require('../lib/db');
const lib   = require('../lib/library');
const USERS_FILE = path.join(__dirname, '..', 'users.json');
function _loadUsers() {
  try { return JSON.parse(fs.readFileSync(USERS_FILE, 'utf8')); }
  catch { return { admins: [], verified: [], blocked: [], settings: {} }; }
}
function _saveUsers(u) { fs.writeFileSync(USERS_FILE, JSON.stringify(u, null, 2)); }
function _normNumber(n) {
  return String(n || '').replace(/[^\d]/g, '');
}
let _legacyHandleAdmin = null;
let _pluginManagerRef  = null;
async function admin(args) {
  const { sock, jid, ctx, intent, role, helpers } = args;
  const cleaned = intent.args || '';
  const tokens = cleaned.split(/\s+/);
  const sub = (tokens[1] || '').toLowerCase();
  if (sub === 'role' && tokens[2] && tokens[3]) {
    const num = _normNumber(tokens[2]);
    const newRole = tokens[3].toLowerCase();
    if (!['free', 'verified', 'admin', 'blocked'].includes(newRole)) {
      return sock.sendMessage(jid, { text: 'Usage: */admin role <number> free|verified|admin|blocked*' }, { quoted: ctx });
    }
    if (!num) return sock.sendMessage(jid, { text: 'Need a phone number.' }, { quoted: ctx });
    const u = _loadUsers();
    const stripped = (list) => list.filter(j => _normNumber(j) !== num);
    u.admins = stripped(u.admins); u.verified = stripped(u.verified); u.blocked = stripped(u.blocked);
    if (newRole === 'admin')    u.admins.push(num + '@s.whatsapp.net');
    if (newRole === 'verified') u.verified.push(num + '@s.whatsapp.net');
    if (newRole === 'blocked')  u.blocked.push(num + '@s.whatsapp.net');
    _saveUsers(u);
    db.setRole(num + '@s.whatsapp.net', newRole);
    db.audit('admin.role', helpers.senderJid, `${num}=${newRole}`);
    return sock.sendMessage(jid, { text: `✅ ${num} → *${newRole}*` }, { quoted: ctx });
  }
  if (sub === 'quota' && tokens[2] && tokens[3]) {
    const num = _normNumber(tokens[2]);
    const mb  = parseInt(tokens[3], 10);
    if (!num || !Number.isFinite(mb) || mb < 0) {
      return sock.sendMessage(jid, { text: 'Usage: */admin quota <number> <mb>*  e.g. */admin quota 92300000000 20480*' }, { quoted: ctx });
    }
    db.setQuota(num + '@s.whatsapp.net', mb);
    db.audit('admin.quota', helpers.senderJid, `${num}=${mb}MB/day`);
    return sock.sendMessage(jid, { text: `✅ ${num} daily quota → *${(mb / 1024).toFixed(2)} GB/day*` }, { quoted: ctx });
  }
  if (sub === 'pitch') {
    const u = _loadUsers();
    const all = db.listUsers();
    const free = all.filter(r => r.role === 'free' && !u.blocked.some(b => _normNumber(b) === _normNumber(r.jid)));
    const text = fmt.premiumPitch(`Upgrade to *${fmt.brand().name} Premium*`) + fmt.brandFooter();
    let sent = 0, failed = 0;
    for (const r of free) {
      try { await sock.sendMessage(r.jid, { text }); sent++; }
      catch { failed++; }
    }
    db.audit('admin.pitch', helpers.senderJid, `sent=${sent} failed=${failed} target=free`);
    return sock.sendMessage(jid, { text: `📣 Pitch broadcast: *${sent} sent*, ${failed} failed (out of ${free.length} free users).` }, { quoted: ctx });
  }
  if (sub === 'plugins') {
    if (!_pluginManagerRef) return sock.sendMessage(jid, { text: 'plugin manager unavailable' }, { quoted: ctx });
    const list = _pluginManagerRef.list();
    const body = `🔌 *Loaded plugins (${list.length})*\n\n` +
                 list.map(p => `• *${p.name}* v${p.version} — ${p.intents.join(', ')}`).join('\n');
    return sock.sendMessage(jid, { text: body }, { quoted: ctx });
  }
  if (sub === 'users') {
    const which = (tokens[2] || '').toLowerCase() || 'all';
    const all = which === 'all' ? db.listUsers() : db.listUsers(which);
    const top = all.slice(0, 30).map(r => `  • ${r.jid.replace('@s.whatsapp.net','')}  ${r.role}  q=${r.daily_quota_mb}MB`);
    return sock.sendMessage(jid, {
      text: `👥 *Bot users (${all.length}${which === 'all' ? '' : ' ' + which})*\n\n` + top.join('\n'),
    }, { quoted: ctx });
  }
  if (typeof _legacyHandleAdmin === 'function') {
    return _legacyHandleAdmin(sock, jid, cleaned, ctx, helpers.botJid, helpers.botLid);
  }
  return sock.sendMessage(jid, { text: `❓ Unknown admin sub-command "${sub}". Try */admin list*.` }, { quoted: ctx });
}
async function relogin({ sock, jid, ctx }) {
  const fetch = require('node-fetch');
  const STREAM_API = process.env.STREAM_API || 'http://localhost:5000';
  const botKey = process.env.BOT_API_KEY || '';
  const msisdn = process.env.JAZZDRIVE_MSISDN || '';
  try {
    const r = await fetch(`${STREAM_API}/api/jd/send-otp`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(botKey ? { 'X-Bot-Key': botKey } : {}),
      },
      body: JSON.stringify({ msisdn }),
      timeout: 12000,
    });
    if (r.ok) {
      const d = await r.json().catch(() => ({}));
      if (d.ok) {
        return sock.sendMessage(jid, {
          text: `🔄 *OTP sent!*\n\nCheck SMS on *${d.msisdn || msisdn}* then use:\n*/otp <code>*\n\nOr paste tokens via the hub Scan page.`,
        }, { quoted: ctx });
      }
      return sock.sendMessage(jid, { text: `⚠️ Hub rejected OTP trigger: ${d.error || 'unknown error'}\n\nOpen hub Scan page manually.` }, { quoted: ctx });
    }
    throw new Error(`Hub returned HTTP ${r.status}`);
  } catch (e) {
    return sock.sendMessage(jid, {
      text: `⚠️ *Could not auto-trigger OTP*\n\n*${e.message}*\n\nOpen the hub Scan page → request OTP manually.\nOr paste your tokens from browser DevTools.`,
    }, { quoted: ctx });
  }
}
async function otp({ sock, jid, ctx, intent }) {
  const stream = require('../lib/streamApi');
  const code = (intent.args || '').trim();
  if (!/^\d{3,8}$/.test(code)) return sock.sendMessage(jid, { text: 'Usage: */otp 1234*' }, { quoted: ctx });
  const r = await stream.submitOtp(code);
  return sock.sendMessage(jid, { text: r.ok ? `✅ OTP *${code}* sent to Radd-Flix.` : `❌ ${r.error || 'failed'}` }, { quoted: ctx });
}
module.exports = {
  name: 'admin',
  version: '2.0.0',
  init(ctx) {
    _legacyHandleAdmin = ctx && ctx.legacyHandleAdmin;
    _pluginManagerRef  = ctx && ctx.pluginManager;
  },
  commands: [
    { intent: 'admin',   role: 'admin', handler: admin },
    { intent: 'relogin', role: 'admin', handler: relogin },
    { intent: 'otp',     role: 'admin', handler: otp },
  ],
};